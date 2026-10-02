import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/request_history.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../settings/screens/usage_stats_screen.dart';
import '../../api_management/providers/api_provider.dart';
import '../screens/test_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../providers/history_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedIds = {};
  final Map<String, String> _prettyCache = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<HistoryProvider>().loadHistory();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: '搜索历史...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('请求历史'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: '用量统计',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const UsageStatsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清空历史'),
                  content: const Text('确定要清空所有请求历史吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<HistoryProvider>().clearHistory();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('历史已清空')),
                        );
                      },
                      child: const Text('清空', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<HistoryProvider>(
        builder: (context, provider, child) {
          if (provider.history.isEmpty) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final emptyColor = isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: emptyColor),
                  const SizedBox(height: 16),
                  Text('暂无请求历史', style: TextStyle(fontSize: 18, color: emptyColor)),
                  const SizedBox(height: 8),
                  Text('测试API后会自动记录', style: TextStyle(fontSize: 14, color: emptyColor)),
                ],
              ),
            );
          }

          final filtered = _searchQuery.isEmpty
              ? provider.history
              : provider.history.where((h) {
                  final q = _searchQuery.toLowerCase();
                  return h.endpoint.toLowerCase().contains(q) ||
                      h.model.toLowerCase().contains(q) ||
                      h.requestBody.toString().toLowerCase().contains(q) ||
                      (h.responseBody?.toString().toLowerCase().contains(q) ?? false);
                }).toList();
          final content = ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final item = filtered[index];
              return _buildHistoryItem(context, item);
            },
          );

          if (isWide) {
            return CenteredContent(maxWidth: 700, child: content);
          }
          return content;
        },
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, RequestHistory item) {
    final isSuccess = item.statusCode != null && item.statusCode! >= 200 && item.statusCode! < 300;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedIds.add(item.id);
            } else {
              _expandedIds.remove(item.id);
              _prettyCache.remove(item.id);
              _prettyCache.remove('${item.id}:resp');
            }
          });
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? AppColors.success : AppColors.error,
          ),
        ),
        title: Text(
          item.endpoint,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _buildSubtitle(item, context),
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.duration != null)
              Text(
                '${item.duration}ms',
                style: TextStyle(
                  color: item.duration! < 1000 ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.replay, size: 16),
              onPressed: () => _retest(context, item),
              tooltip: '用此配置重测',
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                _showHistoryDetail(context, item);
              },
              tooltip: '查看详情',
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLazySection('请求体', item.id, () => _prettyJson(item.requestBody), context),
                const SizedBox(height: 16),
                if (item.responseBody != null)
                  _buildLazySection(
                      '响应体',
                      '${item.id}:resp',
                      () => _prettyJson(item.responseBody!),
                      context),
                if (item.statusCode != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('状态码: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSuccess ? AppColors.success : AppColors.error,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${item.statusCode}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一键重测：跳回测试页并预填历史的模型与请求体。
  Future<void> _retest(BuildContext context, RequestHistory item) async {
    final configs = context.read<ApiProvider>().allApiConfigs;
    ApiConfig? config;
    for (final candidate in configs) {
      if (candidate.id == item.apiConfigId) {
        config = candidate;
        break;
      }
    }
    final messenger = ScaffoldMessenger.of(context);
    if (config == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('原配置已被删除，无法重测')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TestScreen(
          apiConfig: config!,
          initialModel: item.model,
          initialBody: item.requestBody,
        ),
      ),
    );
  }

  String _buildSubtitle(RequestHistory item, BuildContext context) {
    final apiName = context
            .read<HistoryProvider>()
            .apiNames[item.apiConfigId] ??
        '';
    final prefix = apiName.isNotEmpty ? '$apiName · ' : '';
    final tokens = item.totalTokens;
    final suffix = tokens == null ? '' : ' · $tokens tokens';
    return '$prefix${item.model} · ${_formatDate(item.createdAt)}$suffix';
  }

  void _showHistoryDetail(BuildContext context, RequestHistory item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.endpoint),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('模型: ${item.model}'),
              Text('状态码: ${item.statusCode ?? "N/A"}'),
              Text('耗时: ${item.duration ?? "N/A"}ms'),
              Text('时间: ${_formatDate(item.createdAt)}'),
              const Divider(),
              const Text('请求体:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(_prettyJson(item.requestBody)),
              if (item.responseBody != null) ...[
                const SizedBox(height: 8),
                const Text('响应体:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(_prettyJson(item.responseBody!)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// 展开后才构建大 JSON 文本（未展开的行零开销），结果按 id 缓存。
  Widget _buildLazySection(
      String title, String cacheKey, String Function() build, BuildContext context) {
    final text = _prettyCache.putIfAbsent(cacheKey, build);
    return _buildSection(title, text, context);
  }

  String _prettyJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (_) {
      return json.toString();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
