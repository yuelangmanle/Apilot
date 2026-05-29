import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
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
                decoration: const InputDecoration(
                  hintText: '搜索历史...',
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
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('暂无请求历史', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                  SizedBox(height: 8),
                  Text('测试API后会自动记录', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
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
        subtitle: FutureBuilder<String>(
          future: _getApiName(item.apiConfigId),
          builder: (context, snapshot) {
            final apiName = snapshot.data ?? '';
            final prefix = apiName.isNotEmpty ? '$apiName · ' : '';
            return Text(
              '$prefix${item.model} · ${_formatDate(item.createdAt)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            );
          },
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
                _buildSection('请求体', _prettyJson(item.requestBody)),
                const SizedBox(height: 16),
                if (item.responseBody != null)
                  _buildSection('响应体', _prettyJson(item.responseBody!)),
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

  Future<String> _getApiName(String apiConfigId) async {
    try {
      final db = DatabaseService();
      await db.initialize();
      final config = await db.getApiConfig(apiConfigId);
      await db.close();
      return config?.name ?? '';
    } catch (_) {
      return '';
    }
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

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
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
