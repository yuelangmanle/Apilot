import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/api_config.dart';
import '../models/group.dart';

class ImportExportService {
  Future<String> exportConfigs(List<ApiConfig> configs, List<Group> groups) async {
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
          .toList() ?? [];

      return {
        'apiConfigs': configs,
        'groups': groups,
      };
    } catch (e) {
      throw Exception('导入失败: 无效的JSON格式');
    }
  }

  Future<void> saveToFile(String content, String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
  }

  Future<String> loadFromFile(String filepath) async {
    final file = File(filepath);
    return await file.readAsString();
  }
}
