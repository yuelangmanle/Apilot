import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/api_profile_registry.dart';
import '../../../core/services/health_check_service.dart';
import '../../../shared/utils/clipboard_privacy.dart';
import '../../local_llm/screens/api_chat_screen.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/utils/persisted_route.dart';
import '../../api_testing/screens/compare_test_screen.dart';
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
  HealthCheckResult? _health;
  bool _isCheckingHealth = false;
  bool _isRefreshingModels = false;
  final HealthCheckService _healthService = HealthCheckService();

  @override
  void initState() {
    super.initState();
    PersistedRoute.save('api-detail', _apiConfig.id);
    _apiConfig = widget.apiConfig;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_apiConfig.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'compare') _openCompare();
              if (value == 'clone') _cloneConfig();
              if (value == 'export') _showExportFileSheet();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'compare',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.compare_arrows),
                      title: Text('对比测试'))),
              PopupMenuItem(
                  value: 'clone',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.copy_all),
                      title: Text('创建副本'))),
              PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text('导出配置文件'))),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'AI 对话（多轮）',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ApiChatScreen(apiConfig: _apiConfig),
                ),
              );
            },
          ),
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
                  child: Hero(
                    tag: 'api-name-${_apiConfig.id}',
                    child: Text(
                      _apiConfig.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
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
            const SizedBox(height: 12),
            _buildHealthRow(),
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

  Widget _buildHealthRow() {
    final result = _health ?? _healthService.resultFor(_apiConfig.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final badge = healthBadgeText(result);
    final color = switch (result?.status) {
      KeyHealthStatus.ok => AppColors.success,
      KeyHealthStatus.authFailed => AppColors.error,
      KeyHealthStatus.unreachable => AppColors.warning,
      _ => secondary,
    };
    return Row(
      children: [
        SizedBox(
            width: 80,
            child: Text('体检', style: TextStyle(color: secondary, fontSize: 14))),
        Expanded(
          child: Text(badge,
              style: TextStyle(fontSize: 14, color: color)),
        ),
        TextButton(
          onPressed: _isCheckingHealth ? null : _checkHealthNow,
          child: _isCheckingHealth
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('立即体检'),
        ),
      ],
    );
  }

  Future<void> _checkHealthNow() async {
    setState(() => _isCheckingHealth = true);
    try {
      final result = await _healthService.checkOne(_apiConfig);
      if (!mounted) return;
      setState(() => _health = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '体检完成：${healthBadgeText(result)}${result.balanceText == null ? '' : ' · 余额 ${result.balanceText}'}'),
          backgroundColor: result.isOk ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('体检失败: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingHealth = false);
    }
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
              if (copyValue != null && (copyLabel ?? label) == 'API Key') {
                ClipboardPrivacy.copySensitive(copyValue);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('API Key 已复制（60秒后自动清空剪贴板）'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
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

  void _openCompare() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => CompareTestScreen(initialConfig: _apiConfig)),
    );
  }

  /// 克隆：以当前配置为模板进入新建表单（保存时生成新 id）。
  Future<void> _cloneConfig() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ApiFormScreen(apiConfig: _apiConfig),
      ),
    );
  }

  /// 导出单个配置为 JSON 文件：选择含密钥（完整迁移）或脱敏（分享）。
  Future<void> _showExportFileSheet() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出配置文件'),
        content: const Text(
            '含密钥版本可用于完整迁移，请妥善保管；'
            '脱敏版本不含 API Key，适合分享给他人参考。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'sanitized'),
              child: const Text('脱敏导出')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'withKey'),
              child: const Text('含密钥导出')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final includeKey = choice == 'withKey';
    final json = const JsonEncoder.withIndent('  ').convert({
      ..._apiConfig.toJson(),
      'apiKey': includeKey ? _apiConfig.apiKey : '',
    });
    ClipboardPrivacy.copySensitive(json);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(includeKey
            ? '已复制完整配置（含密钥，60秒后自动清空剪贴板）'
            : '已复制脱敏配置（不含 API Key）'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
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
    // 导出片段内嵌明文 Key，与单 Key 复制同样走 60 秒自动清空。
    ClipboardPrivacy.copySensitive(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制为$label（60秒后剪贴板自动清空）'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _refreshModels() async {
    if (_isRefreshingModels) return;
    setState(() => _isRefreshingModels = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingModels = false);
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
