import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一条长期记忆。
class MemoryEntry {
  final String id;
  final String text;
  final List<String> tags;
  final DateTime createdAt;

  const MemoryEntry({
    required this.id,
    required this.text,
    this.tags = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
      };

  static MemoryEntry fromJson(Map<String, dynamic> json) => MemoryEntry(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 长期记忆：把"值得记住的事实"落盘，按相关性检索后注入对话的系统提示词。
///
/// 检索用轻量关键词打分（中文按二元字组、英文按词），无需向量模型即可离线跑；
/// 排序按 命中权重 × 新近度，取前 [maxInject] 条注入。
class MemoryStore {
  MemoryStore._();

  static const int maxEntries = 300;
  static const int maxInject = 6;
  static const int maxEntryChars = 400;
  static const int maxInjectChars = 2400;

  static List<MemoryEntry>? _cache;

  static Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'memory'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'memories.json'));
  }

  static Future<List<MemoryEntry>> all() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!file.existsSync()) {
        _cache = [];
        return _cache!;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        _cache = [];
        return _cache!;
      }
      _cache = decoded
          .whereType<Map>()
          .map((e) => MemoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return _cache!;
    } catch (e) {
      debugPrint('[Memory] 读取失败: $e');
      _cache = [];
      return _cache!;
    }
  }

  static Future<void> _writeAll(List<MemoryEntry> entries) async {
    _cache = entries;
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          jsonEncode(entries.map((e) => e.toJson()).toList()),
          flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[Memory] 写入失败: $e');
    }
  }

  /// 保存一条记忆（完全重复的不重复入库）。
  static Future<MemoryEntry> save(String text,
      {List<String> tags = const []}) async {
    var trimmed = text.trim();
    if (trimmed.length > maxEntryChars) {
      trimmed = trimmed.substring(0, maxEntryChars);
    }
    if (trimmed.isEmpty) throw ArgumentError('记忆内容不能为空');
    if (containsSensitiveData(trimmed)) {
      throw ArgumentError('疑似包含密钥、密码或访问令牌，不会写入长期记忆');
    }
    final entries = List<MemoryEntry>.from(await all());
    for (final existing in entries) {
      if (existing.text.trim() == trimmed) return existing;
    }
    final entry = MemoryEntry(
      id: 'mem_${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
      tags: tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .take(8)
          .toList(),
      createdAt: DateTime.now(),
    );
    entries.insert(0, entry);
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    await _writeAll(entries);
    return entry;
  }

  static Future<void> delete(String id) async {
    final entries = List<MemoryEntry>.from(await all())
      ..removeWhere((e) => e.id == id);
    await _writeAll(entries);
  }

  static Future<void> clear() => _writeAll([]);

  @visibleForTesting
  static void resetCache() => _cache = null;

  /// 取与 [query] 最相关的记忆（关键词打分 + 新近度）。
  static Future<List<MemoryEntry>> recall(String query,
      {int limit = maxInject}) async {
    final entries = await all();
    if (entries.isEmpty) return const [];
    final queryTokens = tokenize(query);
    if (queryTokens.isEmpty) return entries.take(limit).toList();

    final scored = <(MemoryEntry, double)>[];
    final now = DateTime.now();
    for (final entry in entries) {
      final tokens = tokenize(entry.text);
      if (tokens.isEmpty) continue;
      final tagTokens = tokenize(entry.tags.join(' '));
      var overlap = 0.0;
      for (final token in queryTokens) {
        if (tokens.contains(token)) overlap += 1;
      }
      var tagOverlap = 0.0;
      for (final token in queryTokens) {
        if (tagTokens.contains(token)) tagOverlap += 1;
      }
      if (overlap == 0) continue;
      // 正文命中 + 标签命中 + 新近度；标签是辅助信号，不压过正文相关性。
      final coverage = overlap / queryTokens.length;
      final tagCoverage = tagOverlap / queryTokens.length;
      final days = now.difference(entry.createdAt).inDays.clamp(0, 365);
      final recency = 1.0 / (1 + days / 30);
      scored.add((entry, coverage * 0.6 + tagCoverage * 0.15 + recency * 0.25));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  /// 组织成可注入的系统提示词片段。
  static Future<String> buildPromptSection(String query) async {
    final recalled = await recall(query);
    if (recalled.isEmpty) return '';
    final buffer = StringBuffer('以下是关于这位用户的长期记忆（可能在本次对话中有用）：\n');
    for (final entry in recalled) {
      final line = '- ${entry.text}\n';
      if (buffer.length + line.length > maxInjectChars) break;
      buffer.write(line);
    }
    buffer.writeln('（这些是背景信息，不要原样复述；与当前问题无关时忽略。）');
    return buffer.toString();
  }

  /// 分词：英文按词、中文按二元字组（无需分词库）。
  @visibleForTesting
  static Set<String> tokenize(String text) {
    final tokens = <String>{};
    final lower = text.toLowerCase();
    for (final word in RegExp(r'[a-z0-9_]{2,}').allMatches(lower)) {
      tokens.add(word.group(0)!);
    }
    final cjk = RegExp(r'[\u4e00-\u9fa5]+').allMatches(text);
    for (final match in cjk) {
      final run = match.group(0)!;
      if (run.length == 1) {
        tokens.add(run);
        continue;
      }
      for (var i = 0; i + 1 < run.length; i++) {
        tokens.add(run.substring(i, i + 2));
      }
    }
    return tokens;
  }

  /// 记忆是长期落盘数据，拒绝明显的凭据格式，避免用户一句“记住”
  /// 把 API Key、密码或 Bearer Token 永久写入本地文件和后续提示词。
  @visibleForTesting
  static bool containsSensitiveData(String text) {
    return RegExp(
      r'(sk-[a-z0-9]{8,}|api[-_ ]?key\s*[:：=]|密码\s*[:：=]|密钥\s*[:：=]|'
      r'(?<![a-z])bearer\s+[a-z0-9._-]{12,})',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// 启发式：用户明确要求"记住"时自动入库（不用开插件也能生效）。
  static String? extractExplicitMemory(String userMessage) {
    final text = userMessage.trim();
    if (text.isEmpty) return null;
    for (final marker in ['记住', '记得', '请记下', '帮我记']) {
      final index = text.indexOf(marker);
      if (index >= 0) {
        var content = text.substring(index + marker.length);
        content = content.replaceAll(RegExp(r'^[：:，,。.、\s]+'), '');
        if (content.length >= 2) {
          if (containsSensitiveData(content)) return null;
          return content.length > maxEntryChars
              ? content.substring(0, maxEntryChars)
              : content;
        }
      }
    }
    return null;
  }
}
