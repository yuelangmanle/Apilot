import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_management/providers/api_provider.dart';
import '../../sync/services/local_gateway_service.dart';
import '../services/third_party_gateway_grant_channel.dart';

/// 第三方 App 请求"使用 Apilot 本地网关"时的确认页。
///
/// 用户在这里选择网关后端（云端配置 / 本机模型）与模式（仅本机 / 局域网），
/// 确认后启动网关并把 baseUrl + Token 回传给调用方；取消则回传取消结果。
class ThirdPartyGatewayGrantScreen extends StatefulWidget {
  final GatewayGrantRequest request;

  const ThirdPartyGatewayGrantScreen({super.key, required this.request});

  @override
  State<ThirdPartyGatewayGrantScreen> createState() =>
      _ThirdPartyGatewayGrantScreenState();
}

class _ThirdPartyGatewayGrantScreenState
    extends State<ThirdPartyGatewayGrantScreen> {
  final _channel = ThirdPartyGatewayGrantChannel.instance;
  ApiConfig? _selected;
  DownloadedModel? _selectedLocal;
  List<DownloadedModel> _localModels = [];
  late String _targetKind = 'local';
  late bool _lanEnabled = widget.request.wantsLan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = context.read<ApiProvider>().allApiConfigs;
    final files = await ModelDownloadService.listDownloadedModels();
    if (!mounted) return;
    setState(() {
      _selected = configs.isEmpty ? null : configs.first;
      _localModels = files.map((f) => DownloadedModel.fromFile(f)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (_localModels.isNotEmpty) _selectedLocal = _localModels.first;
      // 没有云端配置时只能走本机模型。
      if (_localModels.isEmpty && configs.isNotEmpty) _targetKind = 'cloud';
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final useLocal = _targetKind == 'local';
      final token = _lanEnabled
          ? DateTime.now().microsecondsSinceEpoch.toRadixString(36)
          : null;
      await LocalGatewayService.start(
        useLocal ? null : _selected,
        localModel: useLocal
            ? GatewayLocalModel(
                filePath: _selectedLocal!.filePath,
                name: _selectedLocal!.fileName)
            : null,
        port: LocalGatewayService.defaultPort,
        lanEnabled: _lanEnabled,
        token: token,
      );
      final model = useLocal
          ? LocalGatewayService.localTarget!.id
          : (_selected?.selectedModel ??
              (_selected?.models.isEmpty ?? true
                  ? 'default'
                  : _selected!.models.first));
      await _channel.complete(GatewayGrantPayload(
        baseUrl: 'http://127.0.0.1:${LocalGatewayService.port}/v1',
        token: token,
        model: model,
        scope: _lanEnabled ? 'lan' : 'loopback',
      ));
      if (mounted) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('授权失败：$e'), backgroundColor: AppColors.error));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    await _channel.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final request = widget.request;
    final canConfirm = _targetKind == 'local'
        ? _selectedLocal != null
        : _selected != null;

    return Scaffold(
      appBar: AppBar(title: const Text('第三方请求使用本地网关')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.extension, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.sourceName ??
                              request.callerPackage ??
                              '未知应用',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '这个应用想通过 Apilot 的本地网关访问模型'
                    '${request.wantsLan ? '（请求局域网模式）' : '（仅本机模式）'}。'
                    '确认后 Apilot 会启动网关并把地址与 Token 交给它。',
                    style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
                  ),
                  if (request.callerPackage != null) ...[
                    const SizedBox(height: 4),
                    SelectableText('包名：${request.callerPackage}',
                        style: TextStyle(fontSize: 11, color: secondary)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('用它来提供模型',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'local',
                          icon: Icon(Icons.memory, size: 16),
                          label: Text('本机模型')),
                      ButtonSegment(
                          value: 'cloud',
                          icon: Icon(Icons.cloud_outlined, size: 16),
                          label: Text('云端配置')),
                    ],
                    selected: {_targetKind},
                    onSelectionChanged: (values) =>
                        setState(() => _targetKind = values.first),
                  ),
                  const SizedBox(height: 12),
                  if (_targetKind == 'local')
                    _localModels.isEmpty
                        ? Text('还没有已下载的本地模型', style: TextStyle(
                            fontSize: 12, color: secondary))
                        : DropdownButtonFormField<DownloadedModel>(
                            initialValue: _selectedLocal,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '本机模型（离线，不消耗额度）',
                              border: OutlineInputBorder(),
                            ),
                            items: _localModels
                                .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m.name,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedLocal = value),
                          )
                  else if (_selected == null)
                    Text('还没有云端 API 配置', style: TextStyle(
                        fontSize: 12, color: secondary))
                  else
                    DropdownButtonFormField<ApiConfig>(
                      initialValue: _selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '云端配置（转发，Key 不下发）',
                        border: OutlineInputBorder(),
                      ),
                      items: context
                          .watch<ApiProvider>()
                          .allApiConfigs
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (value) => setState(() => _selected = value),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许局域网设备访问',
                        style: TextStyle(fontSize: 14)),
                    subtitle: const Text('关闭时只有本机 App 能连（最安全）',
                        style: TextStyle(fontSize: 12)),
                    value: _lanEnabled,
                    onChanged: (value) => setState(() => _lanEnabled = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (!canConfirm || _busy) ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_busy ? '授权中…' : '授权并启动网关'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
