import 'package:flutter/material.dart';
import '../services/lan_discovery.dart';
import '../../../core/models/device_info.dart';
import '../../../shared/theme/color_scheme.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final LanDiscoveryService _discoveryService = LanDiscoveryService();
  List<DeviceInfo> _devices = [];

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    await _discoveryService.startDiscovery();
    _discoveryService.devicesStream.listen((devices) {
      setState(() {
        _devices = devices;
      });
    });
  }

  @override
  void dispose() {
    _discoveryService.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () {
              // TODO: Show QR code for pairing
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(
                      Icons.wifi_find,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '正在搜索同一网络下的设备...',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新'),
                      onPressed: () {
                        _discoveryService.stopDiscovery();
                        _startDiscovery();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? const Center(
                    child: Text(
                      '暂未发现其他设备',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: Icon(
                          _getDeviceIcon(device.platform),
                          color: AppColors.primary,
                        ),
                        title: Text(device.name),
                        subtitle: Text(device.ipAddress),
                        trailing: ElevatedButton(
                          onPressed: () {
                            _showSyncDialog(device);
                          },
                          child: const Text('同步'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'macos':
        return Icons.computer;
      case 'windows':
        return Icons.desktop_windows;
      default:
        return Icons.device_unknown;
    }
  }

  void _showSyncDialog(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('与 ${device.name} 同步'),
        content: const Text('选择同步方向：'),
        actions: [
          TextButton(
            onPressed: () {
              // TODO: Send to device
              Navigator.pop(context);
            },
            child: const Text('发送到此设备'),
          ),
          TextButton(
            onPressed: () {
              // TODO: Receive from device
              Navigator.pop(context);
            },
            child: const Text('从此设备接收'),
          ),
          TextButton(
            onPressed: () {
              // TODO: Bidirectional sync
              Navigator.pop(context);
            },
            child: const Text('双向同步'),
          ),
        ],
      ),
    );
  }
}
