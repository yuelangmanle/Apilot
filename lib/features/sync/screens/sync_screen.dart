import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/sync_service.dart';
import '../../../core/models/device_info.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService();
  final DatabaseService _databaseService = DatabaseService();
  List<DeviceInfo> _devices = [];
  bool _isScanning = false;
  DeviceInfo? _localDevice;
  Timer? _refreshTimer;
  String? _syncStatus;

  @override
  void initState() {
    super.initState();
    _initSync();
  }

  Future<void> _initSync() async {
    _localDevice = await _syncService.getLocalDeviceInfo();
    await _syncService.start();

    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _devices = _syncService.discoveredDevices;
          _isScanning = _syncService.isRunning;
        });
      } else {
        timer.cancel();
      }
    });

    setState(() {});
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _syncService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = ResponsiveLayout.isWide(context);

    final content = Column(
      children: [
        _buildLocalDeviceCard(isDark),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                _isScanning ? Icons.wifi_find : Icons.wifi_off,
                color: isDark ? AppColors.darkPrimary : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isScanning ? '已发现 ${_devices.length} 台设备' : '同步服务未启动',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
                onPressed: () {
                  _syncService.stop();
                  _initSync();
                },
              ),
            ],
          ),
        ),
        if (_syncStatus != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(child: Text(_syncStatus!, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _devices.isEmpty ? _buildEmptyState(isDark) : _buildDeviceList(isDark),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: _showQRCode,
            tooltip: '显示配对二维码',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showManualConnect,
            tooltip: '手动连接',
          ),
        ],
      ),
      body: isWide ? CenteredContent(maxWidth: 600, child: content) : content,
    );
  }

  Widget _buildLocalDeviceCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkCardBackground, AppColors.darkSurface]
              : [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.primary).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getPlatformIcon(_localDevice?.platform ?? 'unknown'),
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localDevice?.name ?? '加载中...',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IP: ${_localDevice?.ipAddress ?? '...'}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isScanning ? '在线' : '离线',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, size: 64, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('未发现其他设备', style: TextStyle(fontSize: 18, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('确保设备在同一局域网下', style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('手动输入IP连接'),
            onPressed: _showManualConnect,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(bool isDark) {
    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getPlatformIcon(device.platform), color: AppColors.primary),
            ),
            title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${device.ipAddress} • ${device.platform}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.isOnline ? AppColors.success : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleDeviceAction(value, device),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'send', child: Text('发送配置到此设备')),
                    const PopupMenuItem(value: 'receive', child: Text('从此设备接收配置')),
                    const PopupMenuItem(value: 'sync', child: Text('双向同步')),
                  ],
                ),
              ],
            ),
            onTap: () => _showSyncDialog(device),
          ),
        );
      },
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'android': return Icons.phone_android;
      case 'ios': return Icons.phone_iphone;
      case 'macos': return Icons.laptop_mac;
      case 'windows': return Icons.computer;
      case 'linux': return Icons.computer;
      default: return Icons.devices;
    }
  }

  void _showQRCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配对二维码'),
        content: SizedBox(
          width: 200,
          height: 200,
          child: QrImageView(
            data: '${_localDevice?.ipAddress ?? "unknown"}:${_localDevice?.id ?? ""}',
            version: QrVersions.auto,
            size: 200,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showManualConnect() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动连接'),
        content: TextField(
          controller: ipController,
          decoration: const InputDecoration(
            labelText: '设备IP地址',
            hintText: '例如：192.168.1.100',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _addManualDevice(ipController.text.trim());
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  void _addManualDevice(String ip) {
    if (ip.isEmpty) return;
    final device = DeviceInfo(
      id: 'manual_$ip',
      name: '设备 ($ip)',
      platform: 'unknown',
      ipAddress: ip,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
    setState(() => _devices.add(device));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加设备 $ip'), backgroundColor: AppColors.success),
    );
  }

  void _handleDeviceAction(String action, DeviceInfo device) {
    switch (action) {
      case 'send': _sendToDevice(device); break;
      case 'receive': _receiveFromDevice(device); break;
      case 'sync': _bidirectionalSync(device); break;
    }
  }

  void _showSyncDialog(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('与 ${device.name} 同步'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备: ${device.name}'),
            Text('IP: ${device.ipAddress}'),
            const SizedBox(height: 16),
            const Text('请选择同步方向：'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('发送'),
            onPressed: () { Navigator.pop(context); _sendToDevice(device); },
          ),
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('接收'),
            onPressed: () { Navigator.pop(context); _receiveFromDevice(device); },
          ),
          TextButton.icon(
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('双向'),
            onPressed: () { Navigator.pop(context); _bidirectionalSync(device); },
          ),
        ],
      ),
    );
  }

  Future<void> _sendToDevice(DeviceInfo device) async {
    setState(() => _syncStatus = '正在发送配置到 ${device.name}...');
    try {
      await _databaseService.initialize();
      final configs = await _databaseService.getAllApiConfigs();
      final success = await _syncService.sendConfigs(device, configs);
      setState(() => _syncStatus = success ? '已发送 ${configs.length} 个配置' : '发送失败');
      if (mounted) {
        context.read<ApiProvider>().loadApiConfigs();
      }
    } catch (e) {
      setState(() => _syncStatus = '发送失败: $e');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }

  Future<void> _receiveFromDevice(DeviceInfo device) async {
    setState(() => _syncStatus = '正在从 ${device.name} 接收配置...');
    try {
      final configs = await _syncService.receiveConfigs(device);
      if (configs.isNotEmpty) {
        await _databaseService.initialize();
        for (final config in configs) {
          await _databaseService.insertApiConfig(config);
        }
        setState(() => _syncStatus = '已接收 ${configs.length} 个配置');
        if (mounted) context.read<ApiProvider>().loadApiConfigs();
      } else {
        setState(() => _syncStatus = '未收到配置');
      }
    } catch (e) {
      setState(() => _syncStatus = '接收失败: $e');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }

  Future<void> _bidirectionalSync(DeviceInfo device) async {
    setState(() => _syncStatus = '正在与 ${device.name} 双向同步...');
    try {
      await _databaseService.initialize();
      final localConfigs = await _databaseService.getAllApiConfigs();
      await _syncService.sendConfigs(device, localConfigs);
      final remoteConfigs = await _syncService.receiveConfigs(device);
      final existingIds = localConfigs.map((c) => c.id).toSet();
      final newConfigs = remoteConfigs.where((c) => !existingIds.contains(c.id)).toList();
      for (final config in newConfigs) {
        await _databaseService.insertApiConfig(config);
      }
      setState(() => _syncStatus = '同步完成，新增 ${newConfigs.length} 个配置');
      if (mounted) context.read<ApiProvider>().loadApiConfigs();
    } catch (e) {
      setState(() => _syncStatus = '同步失败: $e');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }
}
