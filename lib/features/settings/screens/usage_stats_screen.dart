import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/cost_estimator.dart';
import '../../../shared/utils/persisted_route.dart';
import '../../../core/services/usage_aggregator.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_testing/providers/history_provider.dart';
import '../../api_management/providers/api_provider.dart';

/// 聚合用量：按配置汇总 token 消耗与请求数（基于本地请求历史）。
class UsageStatsScreen extends StatefulWidget {
  const UsageStatsScreen({super.key});

  @override
  State<UsageStatsScreen> createState() => _UsageStatsScreenState();
}

class _UsageStatsScreenState extends State<UsageStatsScreen> {
  @override
  void initState() {
    super.initState();
    PersistedRoute.save('usage');
    // 重启后直接进入本页时，历史可能尚未加载——主动加载一次，
    // 避免"用量统计看起来被清空"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<HistoryProvider>().loadHistory();
    });
  }

  @override
  void dispose() {
    PersistedRoute.clearIfCurrent('usage');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    final history = context.watch<HistoryProvider>().history;
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final names = {for (final c in configs) c.id: c.name};
    final usages = UsageAggregator.byConfig(history, names: names);
    // 预算上限（可选字段）：按估算成本展示进度。
    final budgets = {
      for (final c in configs)
        if (c.monthlyBudget != null && c.monthlyBudget! > 0)
          c.id: c.monthlyBudget!,
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final totalTokens = usages.fold<int>(0, (sum, u) => sum + u.totalTokens);
    final totalRequests =
        usages.fold<int>(0, (sum, u) => sum + u.requestCount);
    // 成本估算：基于 token 分布 × 本地价格表。
    final costs = <String, double>{};
    for (final item in history) {
      costs[item.apiConfigId] =
          (costs[item.apiConfigId] ?? 0) + CostEstimator.estimateRecord(item);
    }
    final totalCost =
        costs.values.fold<double>(0, (sum, value) => sum + value);

    final content = Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _bigNumber('$totalRequests', '总请求次数'),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: secondary.withValues(alpha: 0.3)),
                Expanded(
                  child: _bigNumber(_formatTokens(totalTokens), '总 Token'),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.payments_outlined,
                  size: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '按本地价格表估算总消耗 ≈ ${CostEstimator.formatUsd(totalCost)}（仅供参考，未知模型按兜底价）',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: usages.isEmpty
              ? Center(
                  child: Text('还没有请求数据\n去测试一个 API 试试',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: usages.length,
                  itemBuilder: (context, index) {
                    final usage = usages[index];
                    final successRate = usage.requestCount == 0
                        ? null
                        : (usage.successCount / usage.requestCount * 100);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: 0.1),
                                child: Text(
                                  usage.configName.isEmpty
                                      ? '?'
                                      : usage.configName.characters.first,
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(usage.configName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${usage.requestCount} 次请求'
                                '${successRate == null ? '' : ' · 成功率 ${successRate.toStringAsFixed(0)}%'}'
                                ' · 输入 ${_formatTokens(usage.promptTokens)} / 输出 ${_formatTokens(usage.completionTokens)}',
                                style: TextStyle(
                                    fontSize: 12, color: secondary),
                              ),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_formatTokens(usage.totalTokens),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary)),
                                  if ((costs[usage.configId] ?? 0) > 0)
                                    Text(
                                        CostEstimator.formatUsd(
                                            costs[usage.configId] ?? 0),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: secondary)),
                                ],
                              ),
                            ),
                            if (budgets[usage.configId] != null) ...[
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: ((costs[usage.configId] ?? 0) /
                                            budgets[usage.configId]!)
                                        .clamp(0.0, 1.0),
                                backgroundColor:
                                    secondary.withValues(alpha: 0.15),
                                color: (costs[usage.configId] ?? 0) >=
                                        budgets[usage.configId]!
                                    ? AppColors.error
                                    : AppColors.primary,
                                minHeight: 4,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '月预算 ${CostEstimator.formatUsd(budgets[usage.configId]!)}'
                                '，已用 ${((costs[usage.configId] ?? 0) / budgets[usage.configId]! * 100).toStringAsFixed(0)}%'
                                '${(costs[usage.configId] ?? 0) >= budgets[usage.configId]! ? '（已超）' : ''}',
                                style: TextStyle(
                                    fontSize: 10, color: secondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '统计基于本机最近 500 条请求历史，仅保存在本机',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('用量统计')),
      body:
          isWide ? CenteredContent(maxWidth: 640, child: content) : content,
    );
  }

  Widget _bigNumber(String value, String label) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: child,
            ),
          ),
          child: Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary))),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(tokens >= 10000000 ? 0 : 1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(tokens >= 10000 ? 0 : 1)}k';
    }
    return '$tokens';
  }
}
