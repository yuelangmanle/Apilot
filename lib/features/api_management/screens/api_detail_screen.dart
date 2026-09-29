import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/api_profile_registry.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/test_screen.dart';
import 'api_form_screen.dart';
import '../providers/api_provider.dart';
import '../services/api_config_export_formatter.dart';

class ApiDetailScreen extends StatefulWidget {
  final ApiConfig apiConfig;

  const ApiDetailScreen({super.key, required this.apiConfig});

  @override
  State<ApiDetailScreen> createState() => _ApiDetailScreenState();
}

class _ApiDetailScreenState extends State<ApiDetailScreen> {
  late ApiConfig _apiConfig;

  @override
  void initState() {
    super.initState();
    _apiConfig = widget.apiConfig;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_apiConfig.name),
        actions: [
          IconButton(
            icon: Icon(
              _apiConfig.isFavorite ? Icons.star : Icons.star_border,
              color: _apiConfig.isFavorite ? AppColors.warning : null,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              try {
                await context.read<ApiProvider>().updateApiConfig(
                      _apiConfig.copyWith(
                          isFavorite: !_apiConfig.isFavorite),
                    );
                if (mounted) navigator.pop(true);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('操作失败: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ApiFormScreen(apiConfig: _apiConfig, isEditing: true),
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
                    _apiConfig.name,
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
            _buildInfoRow(context, 'API地址', _apiConfig.baseUrl,
                canCopy: true, copyLabel: 'API地址'),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              '提供商',
              ApiProfileRegistry.resolve(
                baseUrl: _apiConfig.baseUrl,
                providerId: _apiConfig.providerId,
                protocolId: _apiConfig.protocolId,
              ).providerDisplayName,
              canCopy: false,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              '协议',
              ApiProfileRegistry.resolve(
                baseUrl: _apiConfig.baseUrl,
                providerId: _apiConfig.providerId,
                protocolId: _apiConfig.protocolId,
              ).protocolDisplayName,
              canCopy: false,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(context, 'API Key', _maskApiKey(_apiConfig.apiKey),
                canCopy: true,
                copyValue: _apiConfig.apiKey,
                copyLabel: 'API Key'),
            if (_apiConfig.group != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(context, '分组', _apiConfig.group!, canCopy: false),
            ],
            if (_apiConfig.importSourceName != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                context,
                '导入来源',
                _apiConfig.importSourceName!,
                canCopy: false,
              ),
            ],
            if (_apiConfig.importTrustLevel != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                context,
                '来源可信度',
                _trustLevelLabel(_apiConfig.importTrustLevel!),
                canCopy: false,
              ),
            ],
            const SizedBox(height: 12),
            _buildInfoRow(context, '创建时间', _formatDate(_apiConfig.createdAt),
                canCopy: false),
            const SizedBox(height: 12),
            _buildInfoRow(context, '更新时间', _formatDate(_apiConfig.updatedAt),
                canCopy: false),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value,
      {required bool canCopy, String? copyValue, String? copyLabel}) {
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
    switch (_apiConfig.environment) {
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
        text = _apiConfig.environment;
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
            if (_apiConfig.selectedModel != null) ...[
              _buildInfoRow(
                context,
                '默认模型',
                _apiConfig.selectedModel!,
                canCopy: true,
                copyValue: _apiConfig.selectedModel,
                copyLabel: '默认模型',
              ),
              const SizedBox(height: 8),
            ],
            _buildInfoRow(
              context,
              '目录状态',
              _modelCatalogSummary(),
              canCopy: false,
            ),
            if (_apiConfig.models.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _apiConfig.models.map((model) {
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
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
                    Clipboard.setData(
                        ClipboardData(text: _apiConfig.models.join('\n')));
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
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '未保存模型目录。可设置默认模型，或在支持的服务上刷新模型列表。',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _modelCatalogSummary() {
    final source = switch (_apiConfig.modelSource) {
      'refreshed' => '远端刷新',
      'third_party' => '第三方导入',
      'manual' => '手动维护',
      _ => '未知来源',
    };
    if (_apiConfig.modelsRefreshedAt == null) return '$source · 未记录刷新时间';
    return '$source · ${_formatDate(_apiConfig.modelsRefreshedAt!)}';
  }

  String _trustLevelLabel(String trustLevel) {
    switch (trustLevel) {
      case 'signature_verified':
        return '已验证包签名';
      case 'system_package':
        return '系统可见包名';
      case 'declared':
        return '调用方声明';
      default:
        return '未知';
    }
  }

  Widget _buildTagsSection() {
    if (_apiConfig.tags.isEmpty) return const SizedBox.shrink();

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
              children: _apiConfig.tags.map((tag) {
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
                      builder: (context) => TestScreen(apiConfig: _apiConfig),
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
                  Clipboard.setData(ClipboardData(text: _apiConfig.baseUrl));
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
            onPressed: _refreshModels,
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
            onPressed: _showExportSheet,
            icon: const Icon(Icons.ios_share),
            label: const Text('复制为…（cURL / 环境变量 / SDK 片段）'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  /// 把配置导出成其他工具可直接使用的格式，完成"快速切换"的最后一公里。
  void _showExportSheet() {
    final defaultModel =
        _apiConfig.selectedModel ?? (_apiConfig.models.isEmpty ? '' : _apiConfig.models.first);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('复制为 cURL'),
              subtitle: const Text('可直接在终端执行'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyExported(ApiConfigExportFormatter.toCurl(
                  baseUrl: _apiConfig.baseUrl,
                  apiKey: _apiConfig.apiKey,
                  model: defaultModel,
                ), 'cURL 命令');
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('复制为环境变量'),
              subtitle: const Text('BASE_URL / API_KEY / MODEL'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyExported(ApiConfigExportFormatter.toEnv(
                  name: _apiConfig.name,
                  baseUrl: _apiConfig.baseUrl,
                  apiKey: _apiConfig.apiKey,
                  model: defaultModel.isEmpty ? null : defaultModel,
                ), '环境变量');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('复制为 OpenAI SDK 片段'),
              subtitle: const Text('Python 客户端示例'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyExported(ApiConfigExportFormatter.toOpenAiClientSnippet(
                  baseUrl: _apiConfig.baseUrl,
                  apiKey: _apiConfig.apiKey,
                  model: defaultModel.isEmpty ? 'gpt-3.5-turbo' : defaultModel,
                ), 'SDK 片段');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _copyExported(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制为$label'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _refreshModels() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('正在获取模型列表...'), duration: Duration(seconds: 1)),
    );
    try {
      final result = await ApiService().fetchAvailableModels(_apiConfig);
      if (!mounted) return;
      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? '未获取到模型，请检查地址和 Key'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      final updated = await context.read<ApiProvider>().replaceApiModels(
            _apiConfig,
            result.models,
          );
      if (!mounted) return;
      setState(() => _apiConfig = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('模型列表已同步：${result.models.length} 个模型'),
          backgroundColor: AppColors.success,
        ),
      );
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
