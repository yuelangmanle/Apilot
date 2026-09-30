import '../models/request_history.dart';

/// 单个配置的用量汇总。
class ConfigUsage {
  final String configId;
  final String configName;
  final int requestCount;
  final int successCount;
  final int totalTokens;
  final int promptTokens;
  final int completionTokens;
  final DateTime? lastUsedAt;

  const ConfigUsage({
    required this.configId,
    required this.configName,
    required this.requestCount,
    required this.successCount,
    required this.totalTokens,
    required this.promptTokens,
    required this.completionTokens,
    this.lastUsedAt,
  });
}

/// 请求历史的聚合统计（纯函数，输入历史、输出按配置汇总）。
class UsageAggregator {
  const UsageAggregator._();

  /// names 提供 configId → 显示名映射（历史里已删掉的配置回退为 id）。
  static List<ConfigUsage> byConfig(
    List<RequestHistory> history, {
    Map<String, String> names = const {},
  }) {
    final order = <String>[];
    final stats = <String, _MutableUsage>{};
    for (final item in history) {
      var entry = stats[item.apiConfigId];
      if (entry == null) {
        entry = _MutableUsage();
        stats[item.apiConfigId] = entry;
        order.add(item.apiConfigId);
      }
      entry.requestCount++;
      if (item.statusCode != null &&
          item.statusCode! >= 200 &&
          item.statusCode! < 300) {
        entry.successCount++;
      }
      entry.promptTokens += item.promptTokens ?? 0;
      entry.completionTokens += item.completionTokens ?? 0;
      entry.totalTokens += item.totalTokens ?? 0;
      final at = item.createdAt;
      if (entry.lastUsedAt == null || at.isAfter(entry.lastUsedAt!)) {
        entry.lastUsedAt = at;
      }
    }
    final result = order.map((id) {
      final entry = stats[id]!;
      return ConfigUsage(
        configId: id,
        configName: names[id] ?? id,
        requestCount: entry.requestCount,
        successCount: entry.successCount,
        totalTokens: entry.totalTokens,
        promptTokens: entry.promptTokens,
        completionTokens: entry.completionTokens,
        lastUsedAt: entry.lastUsedAt,
      );
    }).toList()
      ..sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    return result;
  }
}

class _MutableUsage {
  int requestCount = 0;
  int successCount = 0;
  int totalTokens = 0;
  int promptTokens = 0;
  int completionTokens = 0;
  DateTime? lastUsedAt;
}
