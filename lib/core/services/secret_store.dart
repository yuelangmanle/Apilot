import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 主密钥的存取抽象：生产环境走系统安全区（Android Keystore / 各平台
/// 安全存储），失败时回退到应用支持目录下的受限文件；测试注入内存实现。
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class SecureSecretStore implements SecretStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// secure storage 不可用（平台异常、签名问题等）时的兜底位置。
  Directory? _fallbackDir;

  @visibleForTesting
  Future<Directory?> fallbackDirectory() async {
    _fallbackDir ??= await _resolveFallbackDir();
    return _fallbackDir;
  }

  Future<Directory?> _resolveFallbackDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(path.join(support.path, 'secrets'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (e) {
      debugPrint('[Secrets] 兜底密钥目录创建失败: $e');
      return null;
    }
  }

  Future<File?> _fallbackFile(String key) async {
    final dir = await fallbackDirectory();
    if (dir == null) return null;
    return File(path.join(dir.path, '$key.secret'));
  }

  @override
  Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) return value;
    } catch (e) {
      debugPrint('[Secrets] 安全存储读取失败，尝试兜底文件: $e');
    }
    try {
      final file = await _fallbackFile(key);
      if (file != null && file.existsSync()) {
        return file.readAsStringSync();
      }
    } catch (e) {
      debugPrint('[Secrets] 兜底密钥读取失败: $e');
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return;
    } catch (e) {
      debugPrint('[Secrets] 安全存储写入失败，使用兜底文件: $e');
    }
    final file = await _fallbackFile(key);
    if (file == null) {
      throw StateError('无可用位置保存密钥');
    }
    await file.writeAsString(value, flush: true);
    try {
      // POSIX 权限收紧到仅本用户可读（桌面端有效）。
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
  }
}

/// 单例入口：全局唯一的密钥仓库与主密钥。
class AppSecrets {
  static SecretStore _store = SecureSecretStore();
  static const String _masterKeyStorageKey = 'apilot_master_key_v1';

  @visibleForTesting
  static void configureForTesting(SecretStore store) {
    _store = store;
    _masterKeyCache = null;
  }

  static String? _masterKeyCache;

  /// 32 字节 Fernet 主密钥（base64url）。首次访问时生成并持久化。
  static Future<String> masterKeyBase64() async {
    final cached = _masterKeyCache;
    if (cached != null) return cached;

    var key = await _store.read(_masterKeyStorageKey);
    if (key == null || key.isEmpty) {
      key = base64UrlEncode(_randomBytes(32));
      await _store.write(_masterKeyStorageKey, key);
    }
    _masterKeyCache = key;
    return key;
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
