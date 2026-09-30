import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用锁状态机：PIN 哈希存储（盐+SHA256），启动与从后台返回时锁定。
class AppLockController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const _enabledKey = 'app_lock_enabled';
  static const _pinHashKey = 'app_lock_pin_hash';
  static const _biometricKey = 'app_lock_biometric';

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

  static String hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinHashKey) != null;
  }

  /// 启用应用锁并设置 PIN。失败抛 StateError。
  Future<void> enable(String pin) async {
    if (pin.length < 4) throw StateError('PIN 至少 4 位');
    final prefs = await SharedPreferences.getInstance();
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(_pinHashKey, '$salt:${hashPin(pin, salt)}');
    await prefs.setBool(_enabledKey, true);
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

  /// 生物识别通过后的放行通道：不做 PIN 校验（系统认证即凭证）。
  /// 只在应用锁与生物识别都已开启时生效。
  void unlockViaBiometric() {
    if (!_enabled || !_biometricEnabled || !_locked) return;
    _locked = false;
    notifyListeners();
  }

  /// 校验 PIN。成功即解锁并返回 true。
  Future<bool> unlock(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinHashKey);
    if (stored == null) return false;
    final index = stored.indexOf(':');
    if (index <= 0) return false;
    final salt = stored.substring(0, index);
    final expected = stored.substring(index + 1);
    if (hashPin(pin, salt) != expected) return false;
    _locked = false;
    notifyListeners();
    return true;
  }

  /// 关闭应用锁：需要先通过 [unlock] 验证。
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.setBool(_biometricKey, false);
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
