import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试页 Prompt 预设：保存常用请求体，一键填回表单。
/// 存储在 SharedPreferences（数量小、结构简单，无需建表）。
class PromptPreset {
  final String name;
  final String? model;
  final Map<String, dynamic> body;

  const PromptPreset({
    required this.name,
    this.model,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (model != null) 'model': model,
        'body': body,
      };

  static PromptPreset fromJson(Map<String, dynamic> json) => PromptPreset(
        name: json['name'] as String,
        model: json['model'] as String?,
        body: Map<String, dynamic>.from(json['body'] as Map),
      );
}

class PromptPresetStore {
  static const _prefsKey = 'apilot_prompt_presets';

  static Future<List<PromptPreset>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => PromptPreset.fromJson(
              Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('[Presets] 读取失败: $e');
      return const [];
    }
  }

  static Future<void> save(PromptPreset preset) async {
    final all = await loadAll();
    // 同名覆盖。
    all.removeWhere((item) => item.name == preset.name);
    all.insert(0, preset);
    await _writeAll(all.take(50).toList());
  }

  static Future<void> delete(String name) async {
    final all = await loadAll();
    all.removeWhere((item) => item.name == name);
    await _writeAll(all);
  }

  static Future<void> _writeAll(List<PromptPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final item in presets) item.toJson()]),
    );
  }
}
