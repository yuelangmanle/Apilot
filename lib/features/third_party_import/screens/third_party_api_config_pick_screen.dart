import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/api_config.dart';
import '../../../core/models/api_interop_audit.dart';
import '../../../core/models/api_profile.dart';
import '../../../core/services/api_profile_registry.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_management/providers/api_provider.dart';
import '../models/third_party_import_models.dart';
import '../services/third_party_api_config_pick_channel.dart';

class ThirdPartyApiConfigPickScreen extends StatefulWidget {
  final ThirdPartyApiConfigPickRequest request;

  const ThirdPartyApiConfigPickScreen({
    super.key,
    required this.request,
  });

  @override
  State<ThirdPartyApiConfigPickScreen> createState() =>
      _ThirdPartyApiConfigPickScreenState();
}

class _ThirdPartyApiConfigPickScreenState
    extends State<ThirdPartyApiConfigPickScreen> {
  final ThirdPartyApiConfigPickChannel _channel =
      ThirdPartyApiConfigPickChannel.instance;
  bool _isCompleting = false;

  @override
  Widget build(BuildContext context) {
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final isAllMode =
        widget.request.modelMode == ThirdPartyModelTransferMode.all;
    final isV2 = widget.request.isV2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择 API 方案'),
        leading: IconButton(
          tooltip: '取消',
          icon: const Icon(Icons.close),
          onPressed: _isCompleting ? null : _cancel,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.warning.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: AppColors.warning),
                      SizedBox(width: 8),
                      Text(
                        '第三方 App 请求使用已保存配置',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('来源：${widget.request.displaySourceName}'),
                  if (widget.request.sourcePackage != null)
                    Text('包名：${widget.request.sourcePackage}'),
                  const SizedBox(height: 8),
                  Text(
                    isV2
                        ? '默认只授权连接和默认模型；完整模型列表与 API Key 必须由你额外确认。'
                        : isAllMode
                            ? '将返回完整模型列表，并把第一个模型设为默认模型。'
                            : '只返回第一个默认模型，模型列表由对方 App 自行在线获取。',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (isV2) ...[
                    const SizedBox(height: 8),
                    Text(
                      '来源可信度：${_trustLevelLabel(widget.request.trustLevel)}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '选择要授权给对方 App 的 API 方案',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isV2 ? '选择方案后决定本次要交付的附加权限。' : '确认后会将 API 地址、密钥和所需模型信息回传给该 App。',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (configs.isEmpty)
            _EmptyState(onCancel: _cancel)
          else
            ...configs.map(
              (config) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.api, color: AppColors.primary),
                    title: Text(config.name),
                    subtitle: Text(
                      _configSummary(config),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isCompleting ? null : () => _confirm(config),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(ApiConfig config) async {
    if (widget.request.isV2) {
      final grantedScopes = await _showV2AuthorizationDialog(config);
      if (grantedScopes == null || !mounted) return;
      await _complete(config, grantedScopes: grantedScopes);
      return;
    }

    final isAllMode =
        widget.request.modelMode == ThirdPartyModelTransferMode.all;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认授权'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将把“${config.name}”提供给 ${widget.request.displaySourceName}。'),
            const SizedBox(height: 12),
            const Text('该配置包含 API Key，请确认来源可信。'),
            const SizedBox(height: 12),
            Text(
              isAllMode
                  ? '默认模型：${config.models.isEmpty ? '未设置' : config.models.first}\n同时返回 ${config.models.length} 个备选模型。'
                  : '默认模型：${config.models.isEmpty ? '未设置' : config.models.first}\n不返回模型列表。',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认授权'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _complete(config);
  }

  Future<Set<String>?> _showV2AuthorizationDialog(ApiConfig config) async {
    final requestedScopes = widget.request.requestedScopes;
    final optionalGrantedScopes = <String>{};
    final profile = ApiProfileRegistry.resolve(
      baseUrl: config.baseUrl,
      providerId: config.providerId,
      protocolId: config.protocolId,
    );
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canShareModels = requestedScopes.contains(
              ThirdPartyApiConfigScopes.modelsAll,
            );
            final canShareKey = requestedScopes.contains(
              ThirdPartyApiConfigScopes.secretApiKey,
            );
            final selectedModel = config.selectedModel ??
                (config.models.isEmpty ? null : config.models.first);
            return AlertDialog(
              title: const Text('确认 V2 授权'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '将把“${config.name}”提供给 ${widget.request.displaySourceName}。'),
                    const SizedBox(height: 12),
                    Text('提供商：${profile.providerDisplayName}'),
                    Text('协议：${profile.protocolDisplayName}'),
                    Text('默认模型：${selectedModel ?? '未设置'}'),
                    if (canShareModels)
                      CheckboxListTile(
                        value: optionalGrantedScopes.contains(
                          ThirdPartyApiConfigScopes.modelsAll,
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('同时授权完整模型列表'),
                        subtitle: Text('会交付 ${config.models.length} 个已保存模型。'),
                        onChanged: (checked) => setDialogState(() {
                          _toggleOptionalScope(
                            optionalGrantedScopes,
                            ThirdPartyApiConfigScopes.modelsAll,
                            checked == true,
                          );
                        }),
                      ),
                    if (canShareKey)
                      CheckboxListTile(
                        value: optionalGrantedScopes.contains(
                          ThirdPartyApiConfigScopes.secretApiKey,
                        ),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('授权 API Key'),
                        subtitle: const Text('密钥会交付给该第三方 App，请只向可信来源授权。'),
                        onChanged: (checked) => setDialogState(() {
                          _toggleOptionalScope(
                            optionalGrantedScopes,
                            ThirdPartyApiConfigScopes.secretApiKey,
                            checked == true,
                          );
                        }),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final grantedScopes = requestedScopes
                        .where((scope) =>
                            scope != ThirdPartyApiConfigScopes.modelsAll &&
                            scope != ThirdPartyApiConfigScopes.secretApiKey)
                        .toSet()
                      ..addAll(optionalGrantedScopes);
                    Navigator.pop(
                      dialogContext,
                      ThirdPartyApiConfigScopes.normalize(grantedScopes),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('确认授权'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleOptionalScope(
    Set<String> scopes,
    String scope,
    bool shouldGrant,
  ) {
    if (shouldGrant) {
      scopes.add(scope);
    } else {
      scopes.remove(scope);
    }
  }

  Future<void> _complete(
    ApiConfig config, {
    Set<String>? grantedScopes,
  }) async {
    final apiProvider = context.read<ApiProvider>();
    final effectiveScopes = widget.request.isV2
        ? ThirdPartyApiConfigScopes.normalize(
            grantedScopes ?? const <String>{},
          )
        : <String>{
            ThirdPartyApiConfigScopes.connection,
            ThirdPartyApiConfigScopes.modelsDefault,
            if (widget.request.modelMode == ThirdPartyModelTransferMode.all)
              ThirdPartyApiConfigScopes.modelsAll,
            if (config.apiKey.isNotEmpty)
              ThirdPartyApiConfigScopes.secretApiKey,
          };
    setState(() => _isCompleting = true);
    try {
      await _channel.complete(
        ThirdPartyApiConfigPickPayload.fromApiConfig(
          config,
          request: widget.request.isV2 ? widget.request : null,
          modelMode: widget.request.isV2 ? null : widget.request.modelMode,
          grantedScopes: grantedScopes,
        ),
        returnTransport: widget.request.returnTransport,
      );
      try {
        final profile = ApiProfileRegistry.resolve(
          baseUrl: config.baseUrl,
          providerId: config.providerId,
          protocolId: config.protocolId,
        );
        await apiProvider.recordInteropAudit(
          ApiInteropAudit(
            id: const Uuid().v4(),
            direction: ApiInteropAuditDirection.outbound,
            createdAt: DateTime.now(),
            sourceName: widget.request.displaySourceName,
            sourcePackage: widget.request.sourcePackage,
            trustLevel: widget.request.trustLevel,
            apiConfigId: config.id,
            apiConfigName: config.name,
            providerId: profile.providerId,
            protocolId: profile.protocolId,
            grantedScopes: ThirdPartyApiConfigScopes.sort(effectiveScopes),
            selectedModel: config.selectedModel ??
                (config.models.isEmpty ? null : config.models.first),
            modelCount: effectiveScopes.contains(
              ThirdPartyApiConfigScopes.modelsAll,
            )
                ? config.models.length
                : 0,
            apiKeyShared: effectiveScopes.contains(
              ThirdPartyApiConfigScopes.secretApiKey,
            ),
            schemaVersion: widget.request.schemaVersion,
          ),
        );
      } catch (error) {
        debugPrint('无法写入第三方交互审计记录: $error');
      }
      await _channel.finish();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法回传配置：$e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _cancel() async {
    try {
      await _channel.cancel();
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  String _configSummary(ApiConfig config) {
    final profile = ApiProfileRegistry.resolve(
      baseUrl: config.baseUrl,
      providerId: config.providerId,
      protocolId: config.protocolId,
    );
    final selectedModel = config.selectedModel ??
        (config.models.isEmpty ? null : config.models.first);
    final modelText = selectedModel == null ? '未设置默认模型' : '默认：$selectedModel';
    return '${profile.providerDisplayName}  ·  $modelText  ·  ${config.models.length} 个模型';
  }

  String _trustLevelLabel(String trustLevel) {
    switch (trustLevel) {
      case ApiImportTrustLevels.signatureVerified:
        return '已验证包签名';
      case ApiImportTrustLevels.systemPackage:
        return '系统可见包名';
      case ApiImportTrustLevels.declared:
        return '调用方声明';
      default:
        return '未知';
    }
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onCancel;

  const _EmptyState({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon(Icons.api_outlined,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('还没有可授权的 API 方案'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onCancel, child: const Text('关闭')),
        ],
      ),
    );
  }
}
