import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import 'biometric_service.dart';

/// 应用锁状态机：PIN 哈希存储（盐+SHA256），启动与从后台返回时锁定。
class AppLockController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const _enabledKey = 'app_lock_enabled';
  static const _pinHashKey = 'app_lock_pin_hash';
  static const _biometricKey = 'app_lock_biometric';
  static const _failCountKey = 'app_lock_fail_count';
  static const _failLockUntilKey = 'app_lock_fail_lock_until';
  static const _pbkdf2Iterations = 50000;

  /// 连续失败 N 次后的退避起点与倍增系数。
  static const _failBackoffBase = Duration(seconds: 30);

  bool _enabled = false;
  bool _locked = false;
  bool _initialized = false;
  bool _wasInBackground = false;
  bool _biometricEnabled = false;

  bool get enabled => _enabled;
  bool get locked => _locked;
  bool get initialized => _initialized;
  bool get biometricEnabled => _biometricEnabled;

  AppLockController() {
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _biometricEnabled = prefs.getBool(_biometricKey) ?? false;
      _locked = _enabled; // 启动即锁
    } catch (_) {
      _enabled = false;
      _locked = false;
    }
    _initialized = true;
    notifyListeners();
  }

  /// PIN 派生：PBKDF2-HMAC-SHA256，高迭代次数抵御离线爆破。
  static String hashPin(String pin, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(
          utf8.encode(salt), _pbkdf2Iterations, 32));
    return base64.encode(derivator.process(utf8.encode(pin)));
  }

  static String _randomSalt() {
    final random = Random.secure();
    return base64
        .encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinHashKey) != null;
  }

  /// 启用应用锁并设置 PIN。失败抛 StateError。
  Future<void> enable(String pin) async {
    if (pin.length < 4) throw StateError('PIN 至少 4 位');
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomSalt();
    await prefs.setString(_pinHashKey,
        'pbkdf2:$salt:${hashPin(pin, salt)}');
    await prefs.setBool(_enabledKey, true);
    await prefs.setInt(_failCountKey, 0);
    _enabled = true;
    _locked = true;
    notifyListeners();
  }

  /// 开关生物识别解锁（仅应用锁开启时有意义）。
  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
    _biometricEnabled = value;
    notifyListeners();
  }

  /// 发起系统生物识别认证，通过后解锁。
  /// 认证逻辑收在控制器内部：解锁必须经过真实系统认证，不可绕过。
  /// 只在应用锁与生物识别都已开启时生效。返回是否解锁成功。
  Future<bool> authenticateAndUnlock() async {
    if (!_enabled || !_biometricEnabled || !_locked) return false;
    final ok = await BiometricService.authenticate();
    if (!ok) return false;
    _locked = false;
    notifyListeners();
    return true;
  }

  /// 校验 PIN。成功即解锁并返回 true；连续失败会触发时间退避。
  Future<bool> unlock(String pin) async {
    final prefs = await SharedPreferences.getInstance();

    // 退避窗口内直接拒绝，不做校验。
    final lockUntil = prefs.getInt(_failLockUntilKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < lockUntil) return false;

    final stored = prefs.getString(_pinHashKey);
    if (stored == null) return false;

    var ok = false;
    if (stored.startsWith('pbkdf2:')) {
      // 新格式：pbkdf2:<salt>:<hash>
      final rest = stored.substring('pbkdf2:'.length);
      final index = rest.indexOf(':');
      if (index > 0) {
        final salt = rest.substring(0, index);
        final expected = rest.substring(index + 1);
        ok = hashPin(pin, salt) == expected;
      }
    } else {
      // 旧格式（v1.25.0 前）：<salt>:<sha256>，兼容校验一次。
      final index = stored.indexOf(':');
      if (index > 0) {
        final salt = stored.substring(0, index);
        final expected = stored.substring(index + 1);
        ok = sha256.convert(utf8.encode('$salt:$pin')).toString() == expected;
      }
    }

    if (!ok) {
      final fails = (prefs.getInt(_failCountKey) ?? 0) + 1;
      await prefs.setInt(_failCountKey, fails);
      if (fails >= 5) {
        final backoff = _failBackoffBase * (1 << (fails - 5).clamp(0, 6));
        await prefs.setInt(_failLockUntilKey,
            DateTime.now().add(backoff).millisecondsSinceEpoch);
      }
      return false;
    }

    // 成功：清除退避计数；旧格式哈希顺手升级为 PBKDF2。
    await prefs.setInt(_failCountKey, 0);
    await prefs.setInt(_failLockUntilKey, 0);
    if (!stored.startsWith('pbkdf2:')) {
      final salt = _randomSalt();
      await prefs.setString(_pinHashKey,
          'pbkdf2:$salt:${hashPin(pin, salt)}');
    }
    _locked = false;
    notifyListeners();
    return true;
  }

  /// 当前是否处于失败退避窗口（供界面提示剩余秒数）。
  Future<int> backoffRemainingSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = prefs.getInt(_failLockUntilKey) ?? 0;
    final remaining =
        lockUntil - DateTime.now().millisecondsSinceEpoch;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  /// 关闭应用锁：需要先通过 [unlock] 验证。
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.setBool(_biometricKey, false);
    await prefs.setInt(_failCountKey, 0);
    await prefs.setInt(_failLockUntilKey, 0);
    await prefs.remove(_pinHashKey);
    _enabled = false;
    _biometricEnabled = false;
    _locked = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _locked = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
