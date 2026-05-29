import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_service.dart';
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
                  builder: (context) => ApiFormScreen(apiConfig: apiConfig, isEditing: true),
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
            _buildInfoRow(context, 'API地址', apiConfig.baseUrl, canCopy: true, copyLabel: 'API地址'),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'API Key', _maskApiKey(apiConfig.apiKey), canCopy: true, copyValue: apiConfig.apiKey, copyLabel: 'API Key'),
            if (apiConfig.group != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(context, '分组', apiConfig.group!, canCopy: false),
            ],
            const SizedBox(height: 12),
            _buildInfoRow(context, '创建时间', _formatDate(apiConfig.createdAt), canCopy: false),
            const SizedBox(height: 12),
            _buildInfoRow(context, '更新时间', _formatDate(apiConfig.updatedAt), canCopy: false),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {required bool canCopy, String? copyValue, String? copyLabel}) {
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
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyValue ?? value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${copyLabel ?? label} 已复制'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.copy, size: 18, color: AppColors.primary),
            ),
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
        color: color.withOpacity(0.1),
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
                return InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: model));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已复制模型: $model'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Chip(
                    label: Text(model),
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    side: const BorderSide(color: AppColors.primary),
                    deleteIcon: const Icon(Icons.copy, size: 16),
                    onDeleted: () {
                      Clipboard.setData(ClipboardData(text: model));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制模型: $model'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: apiConfig.models.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制所有模型列表'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_all, size: 16),
                label: const Text('复制全部'),
              ),
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
                  backgroundColor: AppColors.secondary.withOpacity(0.1),
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
    return Column(
      children: [
        Row(
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
                    const SnackBar(
                      content: Text('API地址已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.link),
                label: const Text('复制地址'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _refreshModels(context),
            icon: const Icon(Icons.refresh),
            label: const Text('刷新模型列表'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              final configText = '''
API名称: ${apiConfig.name}
API地址: ${apiConfig.baseUrl}
API Key: ${apiConfig.apiKey}
模型列表: ${apiConfig.models.join(', ')}
环境: ${apiConfig.environment}
分组: ${apiConfig.group ?? '无'}
标签: ${apiConfig.tags.join(', ')}
''';
              Clipboard.setData(ClipboardData(text: configText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制完整配置信息'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            icon: const Icon(Icons.content_copy),
            label: const Text('复制完整配置'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshModels(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在获取模型列表...'), duration: Duration(seconds: 1)),
    );
    try {
      final apiService = ApiService();
      final models = await apiService.getAvailableModels(apiConfig);
      if (models.isNotEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('获取到 ${models.length} 个模型'), backgroundColor: AppColors.success),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获取到模型，请检查地址和Key'), backgroundColor: AppColors.warning),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
