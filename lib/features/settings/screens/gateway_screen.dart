import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/api_config.dart';
import '../../../shared/theme/color_scheme.dart';
import 'package:flutter/services.dart';

import '../../../shared/utils/persisted_route.dart';
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
  bool _lanEnabled = false;
  String _gatewayToken = '';
  final String _lanIp = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PersistedRoute.save('gateway');
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _port = prefs.getInt(_portPrefsKey) ?? LocalGatewayService.defaultPort;
      _lanEnabled = prefs.getBool('apilot_gateway_lan') ?? false;
      _gatewayToken = prefs.getString('apilot_gateway_token') ?? '';
    } catch (_) {}
    _detectLanIp();
    if (!mounted) return;
    final configs = context.read<ApiProvider>().allApiConfigs;
    setState(() {
      if (configs.isNotEmpty) _selected = configs.first;
      _loading = false;
    });
  }

  /// 异步获取本机局域网 IPv4（非回环）。
  Future<String> _detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
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
      await prefs.setBool('apilot_gateway_lan', _lanEnabled);
      if (_lanEnabled && _gatewayToken.isEmpty) {
        _gatewayToken = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        await prefs.setString('apilot_gateway_token', _gatewayToken);
      }
      await LocalGatewayService.start(selected,
          port: _port, lanEnabled: _lanEnabled, token: _gatewayToken);
      if (mounted) setState(() {});
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('启动失败：$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  void dispose() {
    PersistedRoute.clearIfCurrent('gateway');
    super.dispose();
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
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('允许局域网设备访问',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                            '其他设备连你的热点/同一 WiFi 后可使用（需带 Token）',
                            style: TextStyle(fontSize: 12)),
                        value: _lanEnabled,
                        onChanged: running
                            ? null
                            : (value) => setState(() {
                                  _lanEnabled = value;
                                  if (value && _gatewayToken.isEmpty) {
                                    _gatewayToken = DateTime.now()
                                        .microsecondsSinceEpoch
                                        .toRadixString(36);
                                  }
                                }),
                      ),
                      if (_lanEnabled) ...[
                        const SizedBox(height: 4),
                        TextField(
                          enabled: !running,
                          controller: TextEditingController(
                              text: _gatewayToken),
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: '网关 Token',
                            helperText: '其他设备请求时需携带 X-Gateway-Token 头',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text: _gatewayToken));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Token 已复制'),
                                      duration: Duration(seconds: 1)),
                                );
                              },
                            ),
                          ),
                          onChanged: (value) =>
                              setState(() => _gatewayToken = value),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (running) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                'http://127.0.0.1:$_port/v1',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold),
                              ),
                              if (_lanEnabled) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  'http://$_lanIp:$_port/v1',
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12),
                                ),
                              ],
                            ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('怎么用（本机内使用）',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(
                        '1. 启动网关，复制上面的地址；\n'
                        '2. 在本机其他支持自定义 API 的 App 里，'
                        '把 API 地址改为该地址，API Key 随便填；\n'
                        '3. 正常对话——请求会经网关转发到所选配置。',
                        style: TextStyle(
                            fontSize: 12, height: 1.6, color: secondary),
                      ),
                      const SizedBox(height: 8),
                      const Text('注意事项',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(
                        '· 网关只监听 127.0.0.1（本机回环），同一台手机上的'
                        '其他 App 可以连，其他设备连不了——这是有意设计，防止 Key 暴露到局域网；\n'
                        '· Apilot 切到后台后可能被安卓冻结导致连不上：'
                        '使用时请保持 Apilot 在前台或分屏，或在系统设置里'
                        '关闭对 Apilot 的电池优化；\n'
                        '· 流式响应原样透传；请求只在本机回环流动，不经外网。',
                        style: TextStyle(
                            fontSize: 12, height: 1.6, color: secondary),
                      ),
                    ],
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
