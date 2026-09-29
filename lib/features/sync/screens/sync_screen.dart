import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/sync_service.dart';
import '../services/bluetooth_sync_service.dart';
import '../utils/qr_sync_payload.dart';
import '../utils/sync_mode_policy.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/device_info.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import 'qr_scanner_screen.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';
import '../../settings/providers/settings_provider.dart';

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
  StreamSubscription<BluetoothIncomingTransferOffer>?
      _incomingOfferSubscription;
  StreamSubscription<BluetoothReceivedTransfer>? _receivedTransferSubscription;
  StreamSubscription<IncomingSyncRequest>? _incomingRequestSubscription;
  bool _isHandlingIncomingRequest = false;
  bool _isTransferBusy = false;
  String? _syncStatus;
  SyncMode _syncMode = SyncMode.wifi;

  @override
  void initState() {
    super.initState();
    // 设置页的"蓝牙同步"开关决定进入本页时的默认传输方式。
    _syncMode = context.read<SettingsProvider>().bluetoothSync
        ? SyncMode.bluetooth
        : SyncMode.wifi;
    _incomingOfferSubscription = _btService.incomingOffers
        .listen((offer) => unawaited(_handleIncomingBluetoothOffer(offer)));
    _receivedTransferSubscription = _btService.receivedTransfers.listen(
        (transfer) => unawaited(_handleReceivedBluetoothTransfer(transfer)));
    _incomingRequestSubscription = _syncService.incomingRequests
        .listen((request) => unawaited(_handleIncomingSyncRequest(request)));
    _initSync();
  }

  Future<void> _initSync() async {
    _localDevice = await _syncService.getLocalDeviceInfo();
    await _syncService.start(enableDiscovery: false);
    await _applySyncMode(clearDevices: false);

    if (!mounted) {
      await _syncService.stop();
      return;
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        if (_syncMode == SyncMode.wifi) {
          _syncService.pruneStaleDevices();
        }
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
    if (shouldRunWifiDiscovery) {
      // 尊重设置页的"自动发现设备"开关。
      final autoDiscovery = context.read<SettingsProvider>().autoDiscovery;
      await _syncService.setDiscoveryEnabled(
        autoDiscovery,
        clearDevices: clearDevices && !autoDiscovery,
      );
      await _btService.stopScan();
      await _btService.stopAdvertising();
    } else {
      await _syncService.setDiscoveryEnabled(false, clearDevices: clearDevices);
      final localDevice =
          _localDevice ?? await _syncService.getLocalDeviceInfo();
      _localDevice = localDevice;
      await _btService.startAdvertising(localDevice);
    }
    if (mounted) _refreshSyncState();
  }

  void _refreshSyncState() {
    setState(() {
      _devices = _syncMode == SyncMode.wifi
          ? _syncService.discoveredDevices
          : _btService.discoveredDevices;
      _isServiceOnline = _syncMode == SyncMode.wifi
          ? _syncService.isRunning
          : _btService.isAdvertising;
      _isDiscoveryActive = _syncMode == SyncMode.wifi
          ? _syncService.isDiscoveryRunning
          : _isBluetoothBusy;
    });
  }

  Future<void> _setSyncMode(SyncMode mode) async {
    if (_syncMode == mode) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _syncMode = mode;
      _syncStatus =
          mode == SyncMode.bluetooth ? '已切换到真实蓝牙传输模式' : '已切换到 WiFi 局域网同步模式';
    });
    try {
      await _applySyncMode(clearDevices: true);
    } catch (e) {
      // 蓝牙未开启/不支持等失败要回退，避免页面卡在不可用模式。
      if (!mounted) return;
      setState(() {
        _syncMode = SyncMode.wifi;
        _syncStatus = '切换失败，已回到 WiFi 模式';
      });
      try {
        await _applySyncMode(clearDevices: true);
      } catch (_) {}
      messenger.showSnackBar(
        SnackBar(
          content: Text('无法切换到蓝牙模式：$e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _incomingOfferSubscription?.cancel();
    _receivedTransferSubscription?.cancel();
    _incomingRequestSubscription?.cancel();
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
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary)),
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
          if (_syncMode == SyncMode.wifi) ...[
            IconButton(
                icon: const Icon(Icons.phonelink),
                onPressed: _scanQRCode,
                tooltip: '扫码连接'),
            IconButton(
                icon: const Icon(Icons.qr_code),
                onPressed: _showQRCode,
                tooltip: '我的二维码'),
            IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _showManualConnect,
                tooltip: '手动连接'),
          ],
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
        return _isBluetoothBusy
            ? '正在发现附近设备...'
            : _btService.isAdvertising
                ? '蓝牙传输已就绪，等待附近设备'
                : '蓝牙传输未就绪';
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
            subtitle: Text(_syncMode == SyncMode.bluetooth
                ? '蓝牙近场 • ${device.platform}'
                : '${device.ipAddress} • ${device.platform}'),
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
          // 固定白底黑码：二维码绘制在对话框表面，暗色模式下
          // 默认黑色模块会隐形，扫码器也只识别高对比配色。
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          Text('IP: ${_localDevice?.ipAddress ?? ""}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('让对方扫描此码连接',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary)),
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
    String? ipError;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('手动连接'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _syncMode == SyncMode.bluetooth
                  ? '输入蓝牙发现到的设备 IP，或对方显示的直连地址'
                  : '输入对方设备的IP地址\n（在对方的"我的二维码"中查看）',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(dialogContext).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              onChanged: (_) {
                if (ipError != null) {
                  setDialogState(() => ipError = null);
                }
              },
              decoration: InputDecoration(
                  labelText: 'IP地址',
                  hintText: '例如：192.168.1.100',
                  errorText: ipError,
                  border: const OutlineInputBorder()),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                final ip = ipController.text.trim();
                if (extractSyncIp(ip) == null) {
                  setDialogState(() => ipError = '请输入有效的 IPv4 地址');
                  return;
                }
                Navigator.pop(context);
                _connectByIP(ip);
              },
              child: const Text('连接'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectByIP(String ip) async {
    if (ip.isEmpty) return;
    setState(() => _syncStatus = '正在连接 $ip ...');

    final device = await _syncService.pingDevice(ip);
    if (!mounted) return;
    if (device != null) {
      await _syncService.upsertDiscoveredDevice(device, sourceIp: ip);
      if (!mounted) return;
      setState(() {
        _devices = _syncService.discoveredDevices;
        _syncStatus = '已连接到 ${device.name} (${device.ipAddress})';
      });
    } else {
      // 连不上就如实告知，不伪造"在线"设备，避免用户对它发起必败的传输。
      setState(() {
        _devices = _syncService.discoveredDevices;
        _syncStatus = '无法连接 $ip，请确认对方已打开同步页面且在同一网络';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法连接 $ip'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
    Future.delayed(const Duration(seconds: 4), () {
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
              Text(_syncMode == SyncMode.bluetooth
                  ? '传输方式：直接蓝牙'
                  : 'IP: ${device.ipAddress}'),
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

  /// 传输期间的忙碌锁：同一时间只允许一个传输任务，防止并发互相覆盖结果。
  Future<void> _runTransferTask(
    DeviceInfo device,
    String taskLabel,
    Future<String> Function() task,
  ) async {
    if (_isTransferBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已有传输正在进行，请等待完成'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    _isTransferBusy = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await task();
      if (!mounted) return;
      setState(() => _syncStatus = message);
      final failed = message.contains('失败');
      messenger.showSnackBar(
        SnackBar(
          content: Text('$taskLabel：$message'),
          backgroundColor: failed ? AppColors.error : AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = '传输失败: $e';
      setState(() => _syncStatus = message);
      messenger.showSnackBar(
        SnackBar(
          content: Text('$taskLabel：$message'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      _isTransferBusy = false;
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _syncStatus = null);
      });
    }
  }

  Future<void> _sendToDevice(DeviceInfo device) {
    return _runTransferTask(device, '发送配置', () async {
      await _databaseService.initialize();
      final configs = await _databaseService.getAllApiConfigs();
      if (configs.isEmpty) return '本机没有任何配置可发送';
      final success = _syncMode == SyncMode.bluetooth
          ? (await _btService.sendPayload(
              device: device,
              payload: _encodeSyncPayload(configs),
              configCount: configs.length,
            ))
              .success
          : await _syncService.sendConfigs(device, configs);
      return success
          ? '已发送 ${configs.length} 个配置'
          : '发送失败（对方可能未确认或未开启同步）';
    });
  }

  Future<void> _receiveFromDevice(DeviceInfo device) {
    return _runTransferTask(device, '接收配置', () async {
      final configs = _syncMode == SyncMode.bluetooth
          ? _decodeSyncPayload(
              await _btService.requestPayload(device: device))
          : await _syncService.receiveConfigs(device);
      if (configs.isEmpty) return '未收到配置';
      final inserted = await _syncService.storeSyncedConfigs(configs);
      if (mounted) {
        unawaited(context.read<ApiProvider>().loadApiConfigs());
      }
      return '已接收 ${configs.length} 个配置，新增 $inserted 个';
    });
  }

  Future<void> _bidirectionalSync(DeviceInfo device) {
    return _runTransferTask(device, '双向同步', () async {
      await _databaseService.initialize();
      final localConfigs = await _databaseService.getAllApiConfigs();
      if (_syncMode == SyncMode.bluetooth) {
        final result = await _btService.sendPayload(
          device: device,
          payload: _encodeSyncPayload(localConfigs),
          configCount: localConfigs.length,
        );
        if (!result.success) throw StateError(result.message);
      } else {
        final success = await _syncService.sendConfigs(device, localConfigs);
        if (!success) throw StateError('对方未确认或未开启同步');
      }
      final remoteConfigs = _syncMode == SyncMode.bluetooth
          ? _decodeSyncPayload(
              await _btService.requestPayload(device: device))
          : await _syncService.receiveConfigs(device);
      final inserted = await _syncService.storeSyncedConfigs(remoteConfigs);
      if (mounted) {
        unawaited(context.read<ApiProvider>().loadApiConfigs());
      }
      return '双向同步完成，新增 $inserted 个配置';
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
      final devices = await _btService.discoverApilotDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _syncStatus = SyncModePolicy.bluetoothDiscoveryStatus(
          discovered: devices.length,
          added: devices.length,
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

  Uint8List _encodeSyncPayload(List<ApiConfig> configs) {
    final payload = SyncService.createSyncPayload(configs);
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  List<ApiConfig> _decodeSyncPayload(Uint8List payload) {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map) throw const FormatException('蓝牙配置内容格式错误');
    return SyncService.parseSyncPayload(Map<String, dynamic>.from(decoded));
  }

  /// WiFi 同步的入站确认：对端要读取或写入配置时，本机必须显式同意。
  Future<void> _handleIncomingSyncRequest(IncomingSyncRequest request) async {
    if (!mounted) {
      request.respond(false);
      return;
    }
    if (_isHandlingIncomingRequest) {
      // 已有确认框弹出时直接拒绝后续请求，避免叠加对话框。
      request.respond(false);
      return;
    }
    _isHandlingIncomingRequest = true;
    try {
      final action = request.isWrite
          ? '向本机写入 ${request.configCount} 个配置'
          : '读取本机已保存的全部 API 配置（包含 API Key）';
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同步请求确认'),
          content: Text('${request.peerAddress} 请求$action。\n\n'
              '拒绝后对方会收到失败提示。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('允许'),
            ),
          ],
        ),
      );
      request.respond(allowed == true);
    } finally {
      _isHandlingIncomingRequest = false;
    }
  }

  Future<void> _handleIncomingBluetoothOffer(
    BluetoothIncomingTransferOffer offer,
  ) async {
    if (!mounted) return;
    final action = offer.operation == BluetoothTransferOperation.push
        ? '向本机发送 ${offer.configCount} 个配置'
        : '读取本机已保存的 API 配置';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('蓝牙传输请求'),
        content: Text(
            '${offer.senderName} 请求通过蓝牙$action。\n\n确认后会直接传输配置，其中可能包含 API Key。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      await _btService.rejectIncomingTransfer(offer.sessionId);
      return;
    }
    try {
      if (offer.operation == BluetoothTransferOperation.pull) {
        await _databaseService.initialize();
        final configs = await _databaseService.getAllApiConfigs();
        await _btService.acceptIncomingTransfer(
          offer.sessionId,
          payload: _encodeSyncPayload(configs),
        );
        if (mounted) {
          setState(() => _syncStatus = '已通过蓝牙发送 ${configs.length} 个配置');
        }
      } else {
        await _btService.acceptIncomingTransfer(offer.sessionId);
        if (mounted) {
          setState(() => _syncStatus = '已接受蓝牙传输，正在接收配置...');
        }
      }
    } catch (error) {
      await _btService.rejectIncomingTransfer(
        offer.sessionId,
        reason: '无法处理蓝牙传输请求',
      );
      if (mounted) setState(() => _syncStatus = '蓝牙传输失败: $error');
    }
  }

  Future<void> _handleReceivedBluetoothTransfer(
    BluetoothReceivedTransfer transfer,
  ) async {
    try {
      final configs = _decodeSyncPayload(transfer.payload);
      final inserted = await _syncService.storeSyncedConfigs(configs);
      await _btService.completeIncomingTransfer(
        transfer.sessionId,
        success: true,
        message: '已接收 ${configs.length} 个配置，新增 $inserted 个',
      );
      if (!mounted) return;
      final provider = context.read<ApiProvider>();
      await provider.loadApiConfigs();
      if (!mounted) return;
      setState(() => _syncStatus = '已通过蓝牙接收 ${configs.length} 个配置');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已通过蓝牙接收 ${configs.length} 个配置'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      await _btService.completeIncomingTransfer(
        transfer.sessionId,
        success: false,
        message: '无法保存收到的配置',
      );
      if (mounted) setState(() => _syncStatus = '蓝牙接收失败: $error');
    }
  }
}
