import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// 用户"固定"到商店的模型条目（来自 AI 精选或粘贴解析）。
class SavedModelEntry {
  final LocalModelInfo info;

  /// 来源标记：ai / paste / manual。
  final String source;

  /// 来源链接或说明（可空）。
  final String? sourceUrl;
  final DateTime addedAt;

  const SavedModelEntry({
    required this.info,
    required this.source,
    this.sourceUrl,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'info': info.toJson(),
        'source': source,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'addedAt': addedAt.toIso8601String(),
      };

  static SavedModelEntry fromJson(Map<String, dynamic> json) => SavedModelEntry(
        info: LocalModelInfo.fromJson(
            Map<String, dynamic>.from(json['info'] as Map? ?? const {})),
        source: json['source'] as String? ?? 'manual',
        sourceUrl: json['sourceUrl'] as String?,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// "我的社区模型"持久化：AI 精选 / 粘贴解析的结果落盘，重启后仍在。
class ModelCatalogStore {
  ModelCatalogStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;

  Future<File> _file() async {
    final base = _overrideDir ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'model_catalog'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'saved_models.json'));
  }

  Future<List<SavedModelEntry>> list() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final entries = decoded
          .whereType<Map>()
          .map((e) => SavedModelEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return entries;
    } catch (e) {
      debugPrint('[CatalogStore] 读取失败: $e');
      return [];
    }
  }

  Future<void> _writeAll(List<SavedModelEntry> entries) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// 新增/更新条目（按 id 去重；重复保存会覆盖并刷新时间）。
  Future<void> save(SavedModelEntry entry) async {
    try {
      final entries = await list();
      entries.removeWhere((e) => e.info.id == entry.info.id);
      entries.insert(0, entry);
      await _writeAll(entries);
    } catch (e) {
      debugPrint('[CatalogStore] 保存失败: $e');
    }
  }

  /// 批量保存（AI 精选一次落多条）。
  Future<int> saveAll(List<SavedModelEntry> newEntries) async {
    if (newEntries.isEmpty) return 0;
    try {
      final entries = await list();
      final ids = newEntries.map((e) => e.info.id).toSet();
      entries.removeWhere((e) => ids.contains(e.info.id));
      entries.insertAll(0, newEntries);
      await _writeAll(entries);
      return newEntries.length;
    } catch (e) {
      debugPrint('[CatalogStore] 批量保存失败: $e');
      return 0;
    }
  }

  Future<void> delete(String id) async {
    try {
      final entries = await list();
      entries.removeWhere((e) => e.info.id == id);
      await _writeAll(entries);
    } catch (e) {
      debugPrint('[CatalogStore] 删除失败: $e');
    }
  }

  Future<bool> contains(String id) async {
    final entries = await list();
    return entries.any((e) => e.info.id == id);
  }
}
