import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/sync_service.dart';
import '../services/bluetooth_sync_service.dart';
import '../utils/sync_mode_policy.dart';
import '../../../core/models/device_info.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import 'qr_scanner_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService();
  final BluetoothSyncService _btService = BluetoothSyncService();
  final DatabaseService _databaseService = DatabaseService();
  List<DeviceInfo> _devices = [];
  bool _isDiscoveryActive = false;
  bool _isServiceOnline = false;
  bool _isBluetoothBusy = false;
  DeviceInfo? _localDevice;
  Timer? _refreshTimer;
  String? _syncStatus;
  SyncMode _syncMode = SyncMode.wifi;

  @override
  void initState() {
    super.initState();
    _initSync();
  }

  Future<void> _initSync() async {
    _localDevice = await _syncService.getLocalDeviceInfo();
    await _syncService.start(enableDiscovery: false);
    await _applySyncMode(clearDevices: false);

    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _refreshSyncState();
      } else {
        timer.cancel();
      }
    });

    setState(() {});
  }

  Future<void> _applySyncMode({bool clearDevices = true}) async {
    final shouldRunWifiDiscovery =
        SyncModePolicy.shouldRunWifiDiscovery(_syncMode);
    await _syncService.setDiscoveryEnabled(
      shouldRunWifiDiscovery,
      clearDevices: clearDevices && !shouldRunWifiDiscovery,
    );
    if (!shouldRunWifiDiscovery) {
      await _btService.stopScan();
    }
    if (mounted) _refreshSyncState();
  }

  void _refreshSyncState() {
    setState(() {
      _devices = _syncService.discoveredDevices;
      _isServiceOnline = _syncService.isRunning;
      _isDiscoveryActive = _syncMode == SyncMode.wifi
          ? _syncService.isDiscoveryRunning
          : _isBluetoothBusy;
    });
  }

  Future<void> _setSyncMode(SyncMode mode) async {
    if (_syncMode == mode) return;
    setState(() {
      _syncMode = mode;
      _syncStatus =
          mode == SyncMode.bluetooth ? '已切换到蓝牙发现模式' : '已切换到 WiFi 局域网发现模式';
    });
    await _applySyncMode(clearDevices: true);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _syncService.stop();
    _btService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = ResponsiveLayout.isWide(context);

    final content = Column(
      children: [
        _buildLocalDeviceCard(isDark),
        // Mode indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(_syncMode == SyncMode.wifi ? Icons.wifi : Icons.bluetooth,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(SyncModePolicy.title(_syncMode),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              if (_syncMode == SyncMode.bluetooth) ...[
                const Spacer(),
                TextButton.icon(
                  icon: Icon(
                      _isBluetoothBusy
                          ? Icons.hourglass_empty
                          : Icons.bluetooth_searching,
                      size: 16),
                  label: Text(_isBluetoothBusy ? '扫描中' : '蓝牙发现'),
                  onPressed:
                      _isBluetoothBusy ? null : _discoverBluetoothDevices,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                  _syncMode == SyncMode.wifi
                      ? (_isDiscoveryActive ? Icons.wifi_find : Icons.wifi_off)
                      : (_isBluetoothBusy
                          ? Icons.bluetooth_searching
                          : Icons.bluetooth),
                  color: isDark ? AppColors.darkPrimary : AppColors.primary,
                  size: 20),
              const SizedBox(width: 8),
              Text(_statusLine(),
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_syncMode == SyncMode.wifi ? '刷新' : '发现'),
                onPressed: _syncMode == SyncMode.wifi
                    ? () async {
                        await _syncService.stop();
                        await _initSync();
                      }
                    : (_isBluetoothBusy ? null : _discoverBluetoothDevices),
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
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const SizedBox(width: 8),
              Expanded(
                  child:
                      Text(_syncStatus!, style: const TextStyle(fontSize: 13)))
            ]),
          ),
        const Divider(height: 1),
        Expanded(
            child: _devices.isEmpty
                ? _buildEmptyState(isDark)
                : _buildDeviceList(isDark)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备同步'),
        actions: [
          IconButton(
              icon: const Icon(Icons.phonelink),
              onPressed: _scanQRCode,
              tooltip: '输入IP连接'),
          IconButton(
              icon: const Icon(Icons.qr_code),
              onPressed: _showQRCode,
              tooltip: '我的二维码'),
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _showManualConnect,
              tooltip: '手动连接'),
        ],
      ),
      body: isWide ? CenteredContent(maxWidth: 600, child: content) : content,
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SegmentedButton<SyncMode>(
          segments: const [
            ButtonSegment(
                value: SyncMode.wifi,
                label: Text('WiFi'),
                icon: Icon(Icons.wifi)),
            ButtonSegment(
                value: SyncMode.bluetooth,
                label: Text('蓝牙'),
                icon: Icon(Icons.bluetooth)),
          ],
          selected: {_syncMode},
          onSelectionChanged: (Set<SyncMode> selection) {
            _setSyncMode(selection.first);
          },
        ),
      ),
    );
  }

  String _statusLine() {
    if (!_isServiceOnline) return '同步服务未启动';
    switch (_syncMode) {
      case SyncMode.wifi:
        return _isDiscoveryActive ? '已发现 ${_devices.length} 台设备' : 'WiFi 发现未启动';
      case SyncMode.bluetooth:
        return _isBluetoothBusy ? '正在蓝牙发现附近设备...' : '蓝牙发现未运行';
    }
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
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(_getPlatformIcon(_localDevice?.platform ?? 'unknown'),
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_localDevice?.name ?? '加载中...',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('IP: ${_localDevice?.ipAddress ?? '...'}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20)),
            child: Text(_isServiceOnline ? '在线' : '离线',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.devices_other,
          size: 64,
          color:
              isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
      const SizedBox(height: 16),
      Text('未发现其他设备',
          style: TextStyle(
              fontSize: 18,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(SyncModePolicy.emptyStateMessage(_syncMode),
            style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary),
            textAlign: TextAlign.center),
      ),
      const SizedBox(height: 24),
      _buildEmptyActions(),
    ]));
  }

  Widget _buildEmptyActions() {
    if (_syncMode == SyncMode.bluetooth) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('蓝牙发现'),
          onPressed: _isBluetoothBusy ? null : _discoverBluetoothDevices,
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('手动连接'),
            onPressed: _showManualConnect),
      ]);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ElevatedButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text('手动连接'),
          onPressed: _showManualConnect),
      const SizedBox(width: 16),
      OutlinedButton.icon(
          icon: const Icon(Icons.qr_code),
          label: const Text('我的二维码'),
          onPressed: _showQRCode),
    ]);
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
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_getPlatformIcon(device.platform),
                  color: AppColors.primary),
            ),
            title: Text(device.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${device.ipAddress} • ${device.platform}'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _handleDeviceAction(value, device),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'send', child: Text('发送配置')),
                const PopupMenuItem(value: 'receive', child: Text('接收配置')),
                const PopupMenuItem(value: 'sync', child: Text('双向同步')),
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
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.computer;
      case 'linux':
        return Icons.computer;
      default:
        return Icons.devices;
    }
  }

  // ========== 二维码 ==========

  void _scanQRCode() async {
    try {
      final scannedIP = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QrScannerScreen()),
      );
      if (scannedIP != null && scannedIP.isNotEmpty) {
        _connectByIP(scannedIP);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫码失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showQRCode() {
    final qrData =
        '${_localDevice?.ipAddress ?? "unknown"}|${_localDevice?.id ?? ""}|${_localDevice?.name ?? ""}';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('我的二维码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                  data: qrData, version: QrVersions.auto, size: 200)),
          const SizedBox(height: 12),
          Text('IP: ${_localDevice?.ipAddress ?? ""}',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('让对方扫描此码连接',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭'))
        ],
      ),
    );
  }

  // ========== 手动连接 ==========

  void _showManualConnect() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动连接'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _syncMode == SyncMode.bluetooth
                ? '输入蓝牙发现到的设备 IP，或对方显示的直连地址'
                : '输入对方设备的IP地址\n（在对方的"我的二维码"中查看）',
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ipController,
            decoration: const InputDecoration(
                labelText: 'IP地址',
                hintText: '例如：192.168.1.100',
                border: OutlineInputBorder()),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectByIP(ipController.text.trim());
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  void _connectByIP(String ip) async {
    if (ip.isEmpty) return;
    setState(() => _syncStatus = '正在连接 $ip ...');

    final device = await _syncService.pingDevice(ip);
    if (device != null) {
      await _syncService.upsertDiscoveredDevice(device, sourceIp: ip);
      setState(() => _devices = _syncService.discoveredDevices);
      setState(() => _syncStatus = '已连接到 ${device.name} (${device.ipAddress})');
    } else {
      // 添加为手动设备
      final manualDevice = DeviceInfo(
        id: 'manual_$ip',
        name: '设备 ($ip)',
        platform: 'unknown',
        ipAddress: ip,
        lastSeen: DateTime.now(),
        isOnline: true,
      );
      await _syncService.upsertDiscoveredDevice(manualDevice, sourceIp: ip);
      setState(() {
        _devices = _syncService.discoveredDevices;
        _syncStatus = '已添加 $ip，请确认对方已开启同步';
      });
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }

  // ========== 同步操作 ==========

  void _handleDeviceAction(String action, DeviceInfo device) {
    switch (action) {
      case 'send':
        _sendToDevice(device);
        break;
      case 'receive':
        _receiveFromDevice(device);
        break;
      case 'sync':
        _bidirectionalSync(device);
        break;
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
            ]),
        actions: [
          TextButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('发送'),
              onPressed: () {
                Navigator.pop(context);
                _sendToDevice(device);
              }),
          TextButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('接收'),
              onPressed: () {
                Navigator.pop(context);
                _receiveFromDevice(device);
              }),
          TextButton.icon(
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('双向'),
              onPressed: () {
                Navigator.pop(context);
                _bidirectionalSync(device);
              }),
        ],
      ),
    );
  }

  Future<void> _sendToDevice(DeviceInfo device) async {
    setState(() => _syncStatus = '正在发送到 ${device.name}...');
    try {
      await _databaseService.initialize();
      final configs = await _databaseService.getAllApiConfigs();
      final success = await _syncService.sendConfigs(device, configs);
      setState(
          () => _syncStatus = success ? '已发送 ${configs.length} 个配置' : '发送失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '已发送 ${configs.length} 个配置到 ${device.name}'
                : '发送到 ${device.name} 失败'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      setState(() => _syncStatus = '发送失败: $e');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }

  Future<void> _receiveFromDevice(DeviceInfo device) async {
    setState(() => _syncStatus = '正在从 ${device.name} 接收...');
    try {
      final configs = await _syncService.receiveConfigs(device);
      if (configs.isNotEmpty) {
        await _databaseService.initialize();
        for (final config in configs) {
          await _databaseService.insertApiConfig(config);
        }
        setState(() => _syncStatus = '已接收 ${configs.length} 个配置');
        if (mounted) context.read<ApiProvider>().loadApiConfigs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('已从 ${device.name} 接收 ${configs.length} 个配置'),
                backgroundColor: AppColors.success),
          );
        }
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
      final newConfigs =
          remoteConfigs.where((c) => !existingIds.contains(c.id)).toList();
      for (final config in newConfigs) {
        await _databaseService.insertApiConfig(config);
      }
      setState(() => _syncStatus = '同步完成，新增 ${newConfigs.length} 个配置');
      if (mounted) context.read<ApiProvider>().loadApiConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('双向同步完成，新增 ${newConfigs.length} 个配置'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      setState(() => _syncStatus = '同步失败: $e');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = null);
    });
  }

  Future<void> _discoverBluetoothDevices() async {
    if (_syncMode != SyncMode.bluetooth) {
      await _setSyncMode(SyncMode.bluetooth);
    } else {
      await _syncService.setDiscoveryEnabled(false, clearDevices: true);
    }
    setState(() {
      _isBluetoothBusy = true;
      _syncStatus = '正在通过蓝牙发现附近的 Apilot 设备...';
    });
    try {
      final localDevice = await _syncService.getLocalDeviceInfo();
      await _btService.startAdvertising(localDevice);
      final devices = await _btService.discoverApilotDevices();
      var added = 0;
      for (final device in devices) {
        final didAdd = await _syncService.upsertDiscoveredDevice(device,
            sourceIp: device.ipAddress);
        if (didAdd) added++;
      }
      if (!mounted) return;
      setState(() {
        _devices = _syncService.discoveredDevices;
        _syncStatus = SyncModePolicy.bluetoothDiscoveryStatus(
          discovered: devices.length,
          added: added,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(devices.isEmpty
              ? '蓝牙未发现 Apilot 设备'
              : '蓝牙发现 ${devices.length} 台 Apilot 设备'),
          backgroundColor:
              devices.isEmpty ? AppColors.warning : AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncStatus = '蓝牙发现失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('蓝牙发现失败: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) {
        setState(() => _isBluetoothBusy = false);
      }
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _syncStatus = null);
      });
    }
  }
}
