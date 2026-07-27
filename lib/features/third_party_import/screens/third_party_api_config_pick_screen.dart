import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/api_config.dart';
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
                    isAllMode
                        ? '将返回完整模型列表，并把第一个模型设为默认模型。'
                        : '只返回第一个默认模型，模型列表由对方 App 自行在线获取。',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
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
          const Text(
            '确认后会将 API 地址、密钥和所需模型信息回传给该 App。',
            style: TextStyle(color: AppColors.textSecondary),
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
                      config.models.isEmpty
                          ? '未保存模型'
                          : '默认：${config.models.first}  ·  ${config.models.length} 个模型',
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

    setState(() => _isCompleting = true);
    try {
      await _channel.complete(
        ThirdPartyApiConfigPickPayload.fromApiConfig(
          config,
          modelMode: widget.request.modelMode,
        ),
      );
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
