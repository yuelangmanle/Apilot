import 'dart:convert';
import '../models/api_config.dart';
import '../models/group.dart';

class ImportExportService {
  Future<String> exportConfigs(
      List<ApiConfig> configs, List<Group> groups) async {
    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'apiConfigs': configs.map((c) => c.toJson()).toList(),
      'groups': groups.map((g) => g.toJson()).toList(),
    };

    return jsonEncode(exportData);
  }

  Future<Map<String, dynamic>> importConfigs(String jsonString) async {
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
    } catch (e) {
      throw Exception('导入失败: 无效的JSON格式');
    }
  }
}
