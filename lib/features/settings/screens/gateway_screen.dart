import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/api_config.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';
import '../../sync/services/local_gateway_service.dart';

/// 本地网关：127.0.0.1 起一个 OpenAI 兼容反代，任意工具指向它即可
/// 使用 Apilot 所选配置的 Key。仅监听回环地址，不对外网暴露。
class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  static const _portPrefsKey = 'apilot_gateway_port';
  ApiConfig? _selected;
  int _port = LocalGatewayService.defaultPort;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _port = prefs.getInt(_portPrefsKey) ?? LocalGatewayService.defaultPort;
    } catch (_) {}
    if (!mounted) return;
    final configs = context.read<ApiProvider>().allApiConfigs;
    setState(() {
      if (configs.isNotEmpty) _selected = configs.first;
      _loading = false;
    });
  }

  Future<void> _toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    if (LocalGatewayService.isRunning) {
      await LocalGatewayService.stop();
      if (mounted) setState(() {});
      messenger.showSnackBar(const SnackBar(content: Text('网关已停止'),
          duration: Duration(seconds: 1)));
      return;
    }
    final selected = _selected;
    if (selected == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_portPrefsKey, _port);
      await LocalGatewayService.start(selected, port: _port);
      if (mounted) setState(() {});
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('启动失败：$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final running = LocalGatewayService.isRunning;
    final isWide = ResponsiveLayout.isWide(context);
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
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
                          Icon(
                            running ? Icons.sensors : Icons.sensors_off,
                            color: running
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(running ? '网关运行中' : '网关未启动',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: running
                                      ? AppColors.success
                                      : AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ApiConfig>(
                        initialValue: _selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '目标配置',
                          border: OutlineInputBorder(),
                        ),
                        items: configs
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: running
                            ? null
                            : (value) =>
                                setState(() => _selected = value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        keyboardType: TextInputType.number,
                        enabled: !running,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(
                            text: '$_port'),
                        onChanged: (value) =>
                            _port = int.tryParse(value) ?? _port,
                      ),
                      const SizedBox(height: 12),
                      if (running) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            'http://127.0.0.1:$_port/v1',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '把其他工具的 base_url 指向上面地址即可（OpenAI 兼容）。'
                          '仅监听本机回环地址，不对外网暴露。',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _selected == null ? null : _toggle,
                          icon: Icon(running
                              ? Icons.stop
                              : Icons.play_arrow),
                          label: Text(running ? '停止网关' : '启动网关'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '说明：网关在 127.0.0.1 上起一个 OpenAI 兼容反代，'
                    '把请求转发到所选配置的真实端点并自动注入鉴权。'
                    '流量只在本机回环，不经外网；流式响应原样透传。',
                    style: TextStyle(fontSize: 12, height: 1.6, color: secondary),
                  ),
                ),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: const Text('本地网关')),
      body: isWide ? Center(child: SizedBox(width: 640, child: content)) : content,
    );
  }
}
