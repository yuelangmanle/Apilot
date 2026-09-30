import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'secret_store.dart';

/// API Key 静态加密：AES-CBC + HMAC-SHA256（Fernet 规范），输出带
/// `enc1:` 前缀的 Fernet token，便于与历史明文共存和灰度迁移。
class ApiKeyCipher {
  static const String prefix = 'enc1:';

  final enc.Encrypter _encrypter;

  ApiKeyCipher._(this._encrypter);

  static Future<ApiKeyCipher> create(SecretStore store) async {
    final keyBase64 = await AppSecrets.masterKeyBase64();
    return ApiKeyCipher.fromKeyBase64(keyBase64);
  }

  factory ApiKeyCipher.fromKeyBase64(String keyBase64) {
    final key = enc.Key.fromBase64(_normalizeBase64(keyBase64));
    if (key.bytes.length != 32) {
      throw ArgumentError('Fernet 主密钥必须是 32 字节');
    }
    return ApiKeyCipher._(enc.Encrypter(enc.Fernet(key)));
  }

  /// 明文 → `enc1:<fernet-token>`；空值原样返回。
  String encrypt(String plaintext) {
    if (plaintext.isEmpty || _isEncrypted(plaintext)) return plaintext;
    return prefix + _encrypter.encrypt(plaintext).base64;
  }

  /// `enc1:` 前缀的密文 → 明文；非密文输入原样返回（历史明文行）。
  ///
  /// 解密失败返回**空字符串**：密文绝不能被当作真实 API Key 外发到
  /// 请求头、备份文件或同步载荷。界面层据此展示空密钥并提示重录。
  String decrypt(String stored) {
    if (!_isEncrypted(stored)) return stored;
    try {
      return _encrypter.decrypt(enc.Encrypted.fromBase64(
        stored.substring(prefix.length),
      ));
    } catch (e) {
      assert(() {
        debugPrint('[Cipher] 解密失败（主密钥不匹配或密文损坏），已置空');
        return true;
      }());
      return '';
    }
  }

  static bool _isEncrypted(String value) => value.startsWith(prefix);

  static String _normalizeBase64(String value) {
    // base64Url 与 base64 的差异字符互补，统一转标准 base64。
    return value.replaceAll('-', '+').replaceAll('_', '/');
  }
}

/// 生成一个新的 32 字节 Fernet 主密钥（base64url），用于密钥轮换或测试。
String generateMasterKeyBase64() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}
