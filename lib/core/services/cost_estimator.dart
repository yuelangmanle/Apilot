import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/request_history.dart';

/// 模型单价（每百万 token，输入/输出），本地可编辑；内置常见模型默认价，
/// 未知模型按"通用兜底价"估算。纯本地计算。
class ModelPrice {
  final double inputPerMillion;
  final double outputPerMillion;

  /// 缓存读/写（每百万），LiteLLM 提供对应字段。
  final double? cacheReadPerMillion;
  final double? cacheWritePerMillion;

  const ModelPrice({
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.cacheReadPerMillion,
    this.cacheWritePerMillion,
  });

  Map<String, dynamic> toJson() => {
        'input': inputPerMillion,
        'output': outputPerMillion,
        if (cacheReadPerMillion != null) 'cacheRead': cacheReadPerMillion,
        if (cacheWritePerMillion != null) 'cacheWrite': cacheWritePerMillion,
      };

  static ModelPrice fromJson(Map<String, dynamic> json) => ModelPrice(
        inputPerMillion: (json['input'] as num?)?.toDouble() ?? 0,
        outputPerMillion: (json['output'] as num?)?.toDouble() ?? 0,
        cacheReadPerMillion: (json['cacheRead'] as num?)?.toDouble(),
        cacheWritePerMillion: (json['cacheWrite'] as num?)?.toDouble(),
      );
}

class CostEstimator {
  static const _prefsKey = 'apilot_model_prices';
  static const _fallback = ModelPrice(inputPerMillion: 1.0, outputPerMillion: 2.0);

  /// 内置默认价（USD / 百万 token）。模型名支持前缀匹配（如 gpt-4o-2024 按 gpt-4o 计）。
  static const Map<String, ModelPrice> defaults = {
    'gpt-4o': ModelPrice(inputPerMillion: 2.5, outputPerMillion: 10),
    'gpt-4o-mini': ModelPrice(inputPerMillion: 0.15, outputPerMillion: 0.6),
    'gpt-4.1': ModelPrice(inputPerMillion: 2, outputPerMillion: 8),
    'gpt-4.1-mini': ModelPrice(inputPerMillion: 0.4, outputPerMillion: 1.6),
    'deepseek-chat': ModelPrice(inputPerMillion: 0.27, outputPerMillion: 1.1),
    'deepseek-reasoner': ModelPrice(inputPerMillion: 0.55, outputPerMillion: 2.19),
    'claude-sonnet-4': ModelPrice(inputPerMillion: 3, outputPerMillion: 15),
    'claude-3-5-haiku': ModelPrice(inputPerMillion: 0.8, outputPerMillion: 4),
    'gemini-2.5-flash': ModelPrice(inputPerMillion: 0.3, outputPerMillion: 2.5),
    'gemini-2.5-pro': ModelPrice(inputPerMillion: 1.25, outputPerMillion: 10),
    'moonshot-v1-8k': ModelPrice(inputPerMillion: 1.66, outputPerMillion: 1.66),
    'glm-4': ModelPrice(inputPerMillion: 0.7, outputPerMillion: 0.7),
  };

  static Map<String, ModelPrice>? _overrides;
  static Map<String, ModelPrice>? _remoteTable;
  static bool _remoteLoading = false;

  /// 从 LiteLLM 公开价格 JSON 静默更新远程价格表（缓存到本地）。
  /// 千余模型、纯公开数据、无需鉴权；失败时沿用上次快照或内置默认。
  static Future<void> refreshRemoteTable() async {
    if (_remoteLoading) return;
    _remoteLoading = true;
    try {
      final response = await http.get(Uri.parse(_litellmUrl)).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200) return;
      // 数 MB 的 JSON 放 isolate 解析，避免主线程首卡。
      final decoded = await Isolate.run(() => jsonDecode(response.body));
      if (decoded is! Map) return;
      final table = <String, ModelPrice>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        final input = value['input_cost_per_token'];
        final output = value['output_cost_per_token'];
        if (input is! num || output is! num) return;
        table[key.toString().toLowerCase()] = ModelPrice(
          inputPerMillion: input * 1000000,
          outputPerMillion: output * 1000000,
          cacheReadPerMillion: value['cache_read_input_token_cost'] is num
              ? (value['cache_read_input_token_cost'] as num) * 1000000
              : null,
          cacheWritePerMillion: value['cache_creation_input_token_cost'] is num
              ? (value['cache_creation_input_token_cost'] as num) * 1000000
              : null,
        );
      });
      if (table.isEmpty) return;
      _remoteTable = table;
      final prefs = await SharedPreferences.getInstance();
      // 只持久化压缩快照（键→四价），避免存整份多 MB 原始 JSON。
      await prefs.setString(_remoteCacheKey, jsonEncode({
        for (final entry in table.entries)
          entry.key: entry.value.toJson(),
      }));
      debugPrint('[Cost] LiteLLM 价格表已更新：${table.length} 个模型');
    } catch (e) {
      debugPrint('[Cost] 价格表更新失败（使用缓存/默认）: $e');
    } finally {
      _remoteLoading = false;
    }
  }

  /// 启动预热：网络更新前先读本地快照，保证估算可用。
  static Future<void> warmRemoteCache() => _loadRemoteCache();

  static Future<void> _loadRemoteCache() async {
    if (_remoteTable != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_remoteCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _remoteTable = decoded.map((key, value) => MapEntry(
            key.toString(),
            ModelPrice.fromJson(Map<String, dynamic>.from(value as Map)),
          ));
    } catch (_) {}
  }

  static const _litellmUrl =
      'https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json';
  static const _remoteCacheKey = 'apilot_price_table_remote';

  /// 用户自定义价（优先于内置默认）。
  static Future<Map<String, ModelPrice>> loadOverrides() async {
    if (_overrides != null) return _overrides!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _overrides = decoded.map((key, value) => MapEntry(
                key.toString(),
                ModelPrice.fromJson(Map<String, dynamic>.from(value as Map)),
              ));
        }
      }
    } catch (e) {
      debugPrint('[Cost] 价格表读取失败: $e');
    }
    return _overrides ??= {};
  }

  /// 编辑价格表（整表覆写）。
  static Future<void> saveOverrides(Map<String, ModelPrice> overrides) async {
    _overrides = overrides;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        for (final entry in overrides.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  static ModelPrice priceFor(String model) {
    // 首次访问时同步可用性依赖异步加载，这里无法 await——
    // 远程缓存在 main 启动时预热；未加载完则按 overrides/default 兜底。
    final overrides = _overrides;
    if (overrides != null) {
      final hit = _match(overrides, model);
      if (hit != null) return hit;
    }
    final remote = _remoteTable;
    if (remote != null) {
      final hit = _match(remote, model);
      if (hit != null) return hit;
    }
    return _match(defaults, model) ?? _fallback;
  }

  static ModelPrice? _match(Map<String, ModelPrice> table, String model) {
    if (table.containsKey(model)) return table[model];
    // 最长前缀优先：gpt-4o-mini 必须先于 gpt-4o 命中（价差大）。
    final lower = model.toLowerCase();
    String? bestKey;
    for (final key in table.keys) {
      if ((lower.startsWith(key) || model.startsWith(key)) &&
          (bestKey == null || key.length > bestKey.length)) {
        bestKey = key;
      }
    }
    return bestKey == null ? null : table[bestKey];
  }

  /// 单条历史记录的成本估算（USD）。
  /// 三档计价：缓存读按缓存价、推理按输出价，其余输入按普通输入价。
  /// 口径差异：OpenAI 的 prompt_tokens 含缓存命中；Anthropic 的
  /// input_tokens 不含——cached > prompt 时视为 Anthropic 口径不回减。
  static double estimateRecord(RequestHistory item) {
    final price = priceFor(item.model);
    final prompt = (item.promptTokens ?? 0) / 1000000;
    final completion = (item.completionTokens ?? 0) / 1000000;
    final cached = (item.cachedTokens ?? 0) / 1000000;
    final cacheReadPrice = price.cacheReadPerMillion ?? price.inputPerMillion;
    final cachedFraction = prompt > 0 ? cached / prompt : 0.0;
    final openAiStyle = cached <= prompt;
    final plainInput = openAiStyle ? prompt - cached : prompt;
    if (cachedFraction >= 1.0 && openAiStyle) {
      return cached * cacheReadPrice + completion * price.outputPerMillion;
    }
    return plainInput * price.inputPerMillion +
        cached * cacheReadPrice +
        completion * price.outputPerMillion;
  }

  static String formatUsd(double value) {
    if (value >= 1) return '\$${value.toStringAsFixed(2)}';
    if (value >= 0.01) return '\$${value.toStringAsFixed(3)}';
    if (value > 0) return '\$${value.toStringAsFixed(5)}';
    return '\$0';
  }
}
