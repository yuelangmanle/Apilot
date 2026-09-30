import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/api_templates.dart';
import '../../../core/models/api_config.dart';

/// 远程社区模板目录：从仓库里的 templates.json 拉取（随版本发布更新），
/// 本地缓存 + 内置兜底。模板与内置列表按 id 去重合并。
class TemplateCatalogService {
  static const _catalogUrl =
      'https://raw.githubusercontent.com/yuelangmanle/Apilot/main/templates.json';
  static const _cacheKey = 'apilot_remote_templates_v1';
  static const _fetchedAtKey = 'apilot_remote_templates_at';

  /// 返回合并后的模板列表：内置在前，社区模板在后（带 community 标记）。
  static Future<TemplateCatalog> loadCatalog() async {
    final bundled = ApiTemplates.templates;
    final remote = await _loadRemote();
    final remoteIds = bundled.map((t) => t.id).toSet();
    final extra = remote
        .where((t) => !remoteIds.contains(t.id))
        .map((t) => t.copyWith())
        .toList();
    return TemplateCatalog(
      builtin: bundled,
      community: extra,
      fetchedAt: await _lastFetchedAt(),
      fromCache: _lastFetchWasCache,
    );
  }

  static bool _lastFetchWasCache = false;

  static Future<List<ApiConfig>> _loadRemote() async {
    // 1) 尝试网络
    try {
      final response = await http
          .get(Uri.parse(_catalogUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final parsed = parseCatalogJson(response.body);
        if (parsed != null) {
          _lastFetchWasCache = false;
          await _saveCache(response.body);
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('[Templates] 远程模板拉取失败，使用缓存/内置: $e');
    }

    // 2) 缓存兜底
    final cached = await _loadCache();
    if (cached != null) {
      _lastFetchWasCache = true;
      return cached;
    }
    _lastFetchWasCache = true;
    return const [];
  }

  /// 解析并校验目录 JSON；结构非法时返回 null（防止脏数据进列表）。
  @visibleForTesting
  static List<ApiConfig>? parseCatalogJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final list = decoded['templates'];
      if (list is! List) return null;
      final result = <ApiConfig>[];
      for (final item in list) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'];
        final name = map['name'];
        final baseUrl = map['baseUrl'];
        if (id is! String ||
            name is! String ||
            baseUrl is! String ||
            !baseUrl.startsWith('http')) {
          continue;
        }
        result.add(ApiConfig(
          id: 'community_$id',
          name: name,
          baseUrl: baseUrl,
          apiKey: '',
          models: (map['models'] as List?)?.cast<String>() ?? const [],
          environment: 'production',
          group: map['group'] is String ? map['group'] as String : '社区',
          tags: [
            ...((map['tags'] as List?)?.cast<String>() ?? const <String>[]),
            'community',
          ],
          isFavorite: false,
          providerId: 'custom',
          protocolId: 'openai_compatible',
        ));
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCache(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      await prefs.setInt(
          _fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<ApiConfig>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      return parseCatalogJson(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> _lastFetchedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_fetchedAtKey);
      return ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }
}

class TemplateCatalog {
  final List<ApiConfig> builtin;
  final List<ApiConfig> community;
  final DateTime? fetchedAt;
  final bool fromCache;

  const TemplateCatalog({
    required this.builtin,
    required this.community,
    this.fetchedAt,
    this.fromCache = false,
  });

  bool get hasCommunity => community.isNotEmpty;
}
