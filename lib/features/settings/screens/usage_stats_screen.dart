import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/usage_aggregator.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_testing/providers/history_provider.dart';
import '../../api_management/providers/api_provider.dart';

/// 聚合用量：按配置汇总 token 消耗与请求数（基于本地请求历史）。
class UsageStatsScreen extends StatelessWidget {
  const UsageStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    final history = context.watch<HistoryProvider>().history;
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final names = {for (final c in configs) c.id: c.name};
    final usages = UsageAggregator.byConfig(history, names: names);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final totalTokens = usages.fold<int>(0, (sum, u) => sum + u.totalTokens);
    final totalRequests =
        usages.fold<int>(0, (sum, u) => sum + u.requestCount);

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
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
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
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                        trailing: Text(
                          _formatTokens(usage.totalTokens),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
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
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
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
