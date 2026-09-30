import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

import '../models/api_config.dart';
import '../models/group.dart';

/// 配置备份导出/导入。支持可选口令加密（PBKDF2 派生密钥 + Fernet 整包加密）。
class ImportExportService {
  static const String _encryptionMarker = 'pbkdf2-fernet-v1';

  /// 从口令派生 Fernet 密钥（PBKDF2-HMAC-SHA256，迭代 20 万次）。
  static enc.Key _keyFromPassword(String password, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(
          Uint8List.fromList(utf8.encode(salt)), 200000, 32));
    return enc.Key(Uint8List.fromList(
        derivator.process(Uint8List.fromList(utf8.encode(password)))));
  }

  /// 导出备份。[password] 非空时整包加密（口令派生密钥，salt 内嵌）。
  Future<String> exportConfigs(List<ApiConfig> configs, List<Group> groups,
      {String? password}) async {
    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'apiConfigs': configs.map((c) => c.toJson()).toList(),
      'groups': groups.map((g) => g.toJson()).toList(),
    };

    final plain = jsonEncode(exportData);
    if (password == null || password.isEmpty) return plain;

    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final encrypter =
        enc.Encrypter(enc.Fernet(_keyFromPassword(password, salt)));
    final token = encrypter.encrypt(plain).base64;
    return jsonEncode({
      'encryption': _encryptionMarker,
      'salt': salt,
      'payload': token,
    });
  }

  /// 导入备份：自动识别口令加密包。[password] 仅在加密包时使用。
  Future<Map<String, dynamic>> importConfigs(String jsonString,
      {String? password}) async {
    dynamic outer;
    try {
      outer = jsonDecode(jsonString);
    } catch (_) {
      throw Exception('导入失败: 无效的JSON格式');
    }
    if (outer is Map && outer['encryption'] == _encryptionMarker) {
      if (password == null || password.isEmpty) {
        throw Exception('该备份文件已加密，需要输入口令');
      }
      final salt = outer['salt'] as String? ?? '';
      final token = outer['payload'] as String? ?? '';
      final encrypter =
          enc.Encrypter(enc.Fernet(_keyFromPassword(password, salt)));
      String plain;
      try {
        plain = encrypter.decrypt(enc.Encrypted.fromBase64(token));
      } catch (_) {
        throw Exception('口令不正确或备份已损坏');
      }
      return _parsePlain(plain);
    }
    return _parsePlain(jsonString);
  }

  Map<String, dynamic> _parsePlain(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final configs = (data['apiConfigs'] as List)
          .map((c) => ApiConfig.fromJson(c as Map<String, dynamic>))
          .toList();

      final groups = (data['groups'] as List?)
              ?.map((g) => Group.fromJson(g as Map<String, dynamic>))
              .toList() ??
          [];
      final exportedAt = data['exportedAt'] is String
          ? DateTime.tryParse(data['exportedAt'] as String)
          : null;

      return {
        'apiConfigs': configs,
        'groups': groups,
        'exportedAt': exportedAt,
      };
    } catch (_) {
      throw Exception('导入失败: 无效的JSON格式');
    }
  }
}
