import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/request_history.dart';

/// 模型单价（每百万 token，输入/输出），本地可编辑；内置常见模型默认价，
/// 未知模型按"通用兜底价"估算。纯本地计算。
class ModelPrice {
  final double inputPerMillion;
  final double outputPerMillion;

  const ModelPrice({
    required this.inputPerMillion,
    required this.outputPerMillion,
  });

  Map<String, dynamic> toJson() => {
        'input': inputPerMillion,
        'output': outputPerMillion,
      };

  static ModelPrice fromJson(Map<String, dynamic> json) => ModelPrice(
        inputPerMillion: (json['input'] as num?)?.toDouble() ?? 0,
        outputPerMillion: (json['output'] as num?)?.toDouble() ?? 0,
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
    final overrides = _overrides;
    if (overrides != null) {
      final hit = _match(overrides, model);
      if (hit != null) return hit;
    }
    return _match(defaults, model) ?? _fallback;
  }

  static ModelPrice? _match(Map<String, ModelPrice> table, String model) {
    if (table.containsKey(model)) return table[model];
    for (final entry in table.entries) {
      if (model.startsWith(entry.key) ||
          model.toLowerCase().startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 单条历史记录的成本估算（USD）。
  static double estimateRecord(RequestHistory item) {
    final price = priceFor(item.model);
    final prompt = (item.promptTokens ?? 0) / 1000000;
    final completion = (item.completionTokens ?? 0) / 1000000;
    return prompt * price.inputPerMillion +
        completion * price.outputPerMillion;
  }

  static String formatUsd(double value) {
    if (value >= 1) return '\$${value.toStringAsFixed(2)}';
    if (value >= 0.01) return '\$${value.toStringAsFixed(3)}';
    if (value > 0) return '\$${value.toStringAsFixed(5)}';
    return '\$0';
  }
}
