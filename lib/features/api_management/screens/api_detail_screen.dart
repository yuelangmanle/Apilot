import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/test_screen.dart';
import 'api_form_screen.dart';
import '../providers/api_provider.dart';

class ApiDetailScreen extends StatelessWidget {
  final ApiConfig apiConfig;

  const ApiDetailScreen({super.key, required this.apiConfig});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(apiConfig.name),
        actions: [
          IconButton(
            icon: Icon(
              apiConfig.isFavorite ? Icons.star : Icons.star_border,
              color: apiConfig.isFavorite ? AppColors.warning : null,
            ),
            onPressed: () {
              context.read<ApiProvider>().updateApiConfig(
                apiConfig.copyWith(isFavorite: !apiConfig.isFavorite),
              );
              Navigator.pop(context, true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ApiFormScreen(apiConfig: apiConfig),
                ),
              );
              if (result == true && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(context),
            const SizedBox(height: 16),
            _buildModelsSection(context),
            const SizedBox(height: 16),
            _buildTagsSection(),
            const SizedBox(height: 24),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.api, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    apiConfig.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildEnvironmentTag(),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('API地址', apiConfig.baseUrl, true),
            const SizedBox(height: 12),
            _buildInfoRow('API Key', _maskApiKey(apiConfig.apiKey), true),
            if (apiConfig.group != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow('分组', apiConfig.group!, false),
            ],
            const SizedBox(height: 12),
            _buildInfoRow('创建时间', _formatDate(apiConfig.createdAt), false),
            const SizedBox(height: 12),
            _buildInfoRow('更新时间', _formatDate(apiConfig.updatedAt), false),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool canCopy) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        if (canCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
            },
          ),
      ],
    );
  }

  Widget _buildEnvironmentTag() {
    Color color;
    String text;
    switch (apiConfig.environment) {
      case 'development':
        color = AppColors.warning;
        text = '开发';
        break;
      case 'testing':
        color = AppColors.primary;
        text = '测试';
        break;
      case 'production':
        color = AppColors.success;
        text = '生产';
        break;
      default:
        color = AppColors.textSecondary;
        text = apiConfig.environment;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildModelsSection(BuildContext context) {
    if (apiConfig.models.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.smart_toy, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  '可用模型',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: apiConfig.models.map((model) {
                return Chip(
                  label: Text(model),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  side: const BorderSide(color: AppColors.primary),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    if (apiConfig.tags.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tag, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  '标签',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: apiConfig.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
                  side: const BorderSide(color: AppColors.secondary),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TestScreen(apiConfig: apiConfig),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('测试API'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: apiConfig.baseUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API地址已复制')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制地址'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
