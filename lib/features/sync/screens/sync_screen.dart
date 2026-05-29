import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/sync_service.dart';
import '../../../core/models/device_info.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';

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

  @override
  void initState() {
    super.initState();
    _initSync();
  }

  Future<void> _initSync() async {
    _localDevice = await _syncService.getLocalDeviceInfo();
    await _syncService.start();
    
    // 定期刷新设备列表
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _devices = _syncService.discoveredDevices;
        });
      } else {
        timer.cancel();
      }
    });
    
    setState(() {});
  }

  @override
  void dispose() {
    _syncService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => _showQRCode(),
            tooltip: '显示配对二维码',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _showScanDialog(),
            tooltip: '输入配对码',
          ),
        ],
      ),
      body: Column(
        children: [
          // 本机信息卡片
          _buildLocalDeviceCard(isDark),
          
          // 扫描状态
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isScanning ? Icons.bluetooth_searching : Icons.wifi_find,
                  color: isDark ? AppColors.darkPrimary : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  _isScanning ? '正在扫描...' : '已发现 ${_devices.length} 台设备',
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
          
          const Divider(height: 1),
          
          // 设备列表
          Expanded(
            child: _devices.isEmpty
                ? _buildEmptyState(isDark)
                : _buildDeviceList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalDeviceCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkCardBackground, AppColors.darkSurface]
              : [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.primary).withOpacity(0.3),
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
                color: Colors.white.withOpacity(0.2),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IP: ${_localDevice?.ipAddress ?? '--'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '平台: ${_localDevice?.platform ?? '--'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code, color: Colors.white),
              onPressed: () => _showQRCode(),
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
          Icon(
            Icons.devices_other,
            size: 64,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '暂未发现其他设备',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请确保其他设备已打开并连接到同一网络',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code),
            label: const Text('使用二维码配对'),
            onPressed: () => _showQRCode(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.darkPrimary : AppColors.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getPlatformIcon(device.platform),
                color: isDark ? AppColors.darkPrimary : AppColors.primary,
              ),
            ),
            title: Text(
              device.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${device.ipAddress} • ${device.platform}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
            trailing: ElevatedButton(
              onPressed: () => _showSyncDialog(device),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('同步'),
            ),
          ),
        );
      },
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.desktop_windows;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.device_unknown;
    }
  }

  void _showQRCode() {
    if (_localDevice == null) return;
    
    final pairingData = {
      'type': 'api_manager_pair',
      'device': _localDevice!.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final pairingString = Uri.encodeComponent(
      Uri(queryParameters: pairingData.map((k, v) => MapEntry(k, v.toString()))).query,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('扫码配对'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: pairingString,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _localDevice!.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _localDevice!.ipAddress,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '请使用另一台设备扫描此二维码',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
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

  void _showScanDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入配对信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入对方设备的 IP 地址进行手动配对：'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                hintText: '例如: 192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                Navigator.pop(context);
                _connectToDevice(ip);
              }
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToDevice(String ip) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在连接到 $ip...')),
    );
    
    // Add the device manually
    final device = DeviceInfo(
      id: 'manual_$ip',
      name: '设备 ($ip)',
      platform: 'unknown',
      ipAddress: ip,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
    
    setState(() {
      _devices.add(device);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加设备 $ip'),
        backgroundColor: AppColors.success,
      ),
    );
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
            label: const Text('发送到此设备'),
            onPressed: () {
              Navigator.pop(context);
              _sendToDevice(device);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('从此设备接收'),
            onPressed: () {
              Navigator.pop(context);
              _receiveFromDevice(device);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('双向同步'),
            onPressed: () {
              Navigator.pop(context);
              _bidirectionalSync(device);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendToDevice(DeviceInfo device) async {
    try {
      await _databaseService.initialize();
      final configs = await _databaseService.getAllApiConfigs();
      await _databaseService.close();

      final success = await _syncService.sendConfigs(device, configs);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
              ? '已发送 ${configs.length} 个配置到 ${device.name}'
              : '发送失败，请检查网络连接'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _receiveFromDevice(DeviceInfo device) async {
    try {
      final configs = await _syncService.receiveConfigs(device);
      
      if (configs.isNotEmpty) {
        await _databaseService.initialize();
        for (final config in configs) {
          await _databaseService.insertApiConfig(config);
        }
        await _databaseService.close();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(configs.isNotEmpty
              ? '已接收 ${configs.length} 个配置'
              : '未收到配置数据'),
            backgroundColor: configs.isNotEmpty ? AppColors.success : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('接收失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _bidirectionalSync(DeviceInfo device) async {
    try {
      await _databaseService.initialize();
      final localConfigs = await _databaseService.getAllApiConfigs();
      
      // 发送本地配置
      await _syncService.sendConfigs(device, localConfigs);
      
      // 接收远程配置
      final remoteConfigs = await _syncService.receiveConfigs(device);
      
      // 合并配置（去重）
      final existingIds = localConfigs.map((c) => c.id).toSet();
      final newConfigs = remoteConfigs.where((c) => !existingIds.contains(c.id)).toList();
      
      for (final config in newConfigs) {
        await _databaseService.insertApiConfig(config);
      }
      
      await _databaseService.close();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('双向同步完成，新增 ${newConfigs.length} 个配置'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
