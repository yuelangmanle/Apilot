import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/models/api_config.dart';

class BluetoothSyncService {
  // Custom UUIDs for our sync service
  static final Guid _serviceUuid = Guid("12345678-1234-1234-1234-123456789abc");
  static final Guid _configCharUuid = Guid("12345678-1234-1234-1234-123456789abd");

  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  final List<BluetoothDevice> _discoveredDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  bool get isScanning => _isScanning;
  bool get isConnected => _connectedDevice != null;
  List<BluetoothDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Check if Bluetooth is available and enabled
  Future<bool> isAvailable() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('[BT] Bluetooth check failed: $e');
      return false;
    }
  }

  /// Turn on Bluetooth (Android only)
  Future<void> turnOn() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      debugPrint('[BT] Turn on failed: $e');
    }
  }

  /// Start scanning for nearby devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredDevices.clear();

    try {
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final device = result.device;
          if (!_discoveredDevices.any((d) => d.remoteId == device.remoteId)) {
            _discoveredDevices.add(device);
            debugPrint('[BT] Found device: ${device.platformName} (${device.remoteId})');
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: [_serviceUuid], // Only find our sync service
      );

      // Also scan without service filter to find any device
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      debugPrint('[BT] Scan failed: $e');
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// Connect to a device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;

      // Discover services
      final services = await device.discoverServices();
      final hasSyncService = services.any((s) => s.uuid == _serviceUuid);

      if (!hasSyncService) {
        debugPrint('[BT] Device does not have sync service');
        // Still connected, might be a generic device
      }

      return true;
    } catch (e) {
      debugPrint('[BT] Connect failed: $e');
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
  }

  /// Send configs via BLE
  Future<bool> sendConfigs(List<ApiConfig> configs) async {
    if (_connectedDevice == null) return false;

    try {
      final services = await _connectedDevice!.discoverServices();
      BluetoothService? syncService;
      for (final s in services) {
        if (s.uuid == _serviceUuid) {
          syncService = s;
          break;
        }
      }

      if (syncService == null) {
        debugPrint('[BT] Sync service not found, trying generic write');
        return false;
      }

      // Find the config characteristic
      BluetoothCharacteristic? configChar;
      for (final c in syncService.characteristics) {
        if (c.uuid == _configCharUuid) {
          configChar = c;
          break;
        }
      }

      if (configChar == null) return false;

      // Serialize configs
      final payload = {
        'version': '1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'configs': configs.map((c) => c.toJson()).toList(),
      };
      final data = utf8.encode(jsonEncode(payload));

      // BLE has MTU limit, split into chunks if needed
      final mtu = await _connectedDevice!.mtu.first;
      final chunkSize = (mtu - 3).clamp(20, 512); // BLE overhead

      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, data.length);
        final chunk = data.sublist(i, end);
        await configChar.write(chunk, withoutResponse: false);
      }

      debugPrint('[BT] Sent ${configs.length} configs via BLE');
      return true;
    } catch (e) {
      debugPrint('[BT] Send failed: $e');
      return false;
    }
  }

  /// Receive configs via BLE
  Future<List<ApiConfig>> receiveConfigs() async {
    if (_connectedDevice == null) return [];

    try {
      final services = await _connectedDevice!.discoverServices();
      BluetoothService? syncService;
      for (final s in services) {
        if (s.uuid == _serviceUuid) {
          syncService = s;
          break;
        }
      }

      if (syncService == null) return [];

      BluetoothCharacteristic? configChar;
      for (final c in syncService.characteristics) {
        if (c.uuid == _configCharUuid) {
          configChar = c;
          break;
        }
      }

      if (configChar == null) return [];

      final data = await configChar.read();
      if (data.isEmpty) return [];

      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final configs = (json['configs'] as List)
          .map((c) => ApiConfig.fromJson(c as Map<String, dynamic>))
          .toList();

      debugPrint('[BT] Received ${configs.length} configs via BLE');
      return configs;
    } catch (e) {
      debugPrint('[BT] Receive failed: $e');
      return [];
    }
  }

  /// Start advertising as a sync server (Android only for now)
  Future<void> startAdvertising() async {
    try {
      // Note: BLE advertising requires platform-specific implementation
      // For now, we rely on scanning from the other device
      debugPrint('[BT] BLE advertising not yet implemented');
    } catch (e) {
      debugPrint('[BT] Advertising failed: $e');
    }
  }

  void dispose() {
    stopScan();
    disconnect();
  }
}
