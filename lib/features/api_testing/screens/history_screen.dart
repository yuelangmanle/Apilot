import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/request_history.dart';
import '../../../shared/theme/color_scheme.dart';
import '../providers/history_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('请求历史'),
        actions: [
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
                  Text(
                    '暂无请求历史',
                    style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '测试API后会自动记录',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.history.length,
            itemBuilder: (context, index) {
              final item = provider.history[index];
              return _buildHistoryItem(context, item);
            },
          );
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
            color: isSuccess ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
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
          '${item.model} • ${_formatDate(item.createdAt)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: item.duration != null
            ? Text(
                '${item.duration}ms',
                style: TextStyle(
                  color: item.duration! < 1000 ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection('请求体', item.requestBody.toString()),
                const SizedBox(height: 16),
                if (item.responseBody != null)
                  _buildSection('响应体', item.responseBody.toString()),
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

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
