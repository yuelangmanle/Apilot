import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/models/device_info.dart';

class BluetoothSyncService {
  static final UUID _serviceUuid =
      UUID.fromString('12345678-1234-1234-1234-123456789abc');
  static final UUID _deviceInfoCharUuid =
      UUID.fromString('12345678-1234-1234-1234-123456789abd');

  final CentralManager _centralManager = CentralManager();
  final PeripheralManager _peripheralManager = PeripheralManager();
  final List<DeviceInfo> _discoveredDevices = [];

  StreamSubscription<DiscoveredEventArgs>? _discoveredSubscription;
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>?
      _readSubscription;
  bool _isScanning = false;
  bool _isAdvertising = false;
  DeviceInfo? _advertisedDevice;
  GATTCharacteristic? _deviceInfoCharacteristic;

  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  List<DeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  @visibleForTesting
  static List<Permission> androidPermissionPlanForSdk({
    required int? sdkInt,
    bool includeAdvertise = false,
  }) {
    if (sdkInt != null && sdkInt < 31) {
      return const [Permission.locationWhenInUse];
    }
    return [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      if (includeAdvertise) Permission.bluetoothAdvertise,
    ];
  }

  @visibleForTesting
  static int? androidSdkIntFromOperatingSystemVersion(String version) {
    final match = RegExp(r'SDK\s+(\d+)').firstMatch(version);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Future<bool> isAvailable() async {
    try {
      await _ensureAndroidBluetoothPermissions();
      final state = _centralManager.state;
      if (state == BluetoothLowEnergyState.poweredOn) return true;
      if (state == BluetoothLowEnergyState.unauthorized && Platform.isAndroid) {
        return await _centralManager.authorize();
      }
      return false;
    } catch (e) {
      debugPrint('[BT] 蓝牙状态检查失败: $e');
      return false;
    }
  }

  Future<void> startAdvertising(DeviceInfo localDevice) async {
    _advertisedDevice = localDevice;
    if (_isAdvertising) return;

    try {
      await _ensureAndroidBluetoothPermissions(includeAdvertise: true);
      if (_peripheralManager.state == BluetoothLowEnergyState.unauthorized &&
          Platform.isAndroid) {
        await _peripheralManager.authorize();
      }
      if (_peripheralManager.state != BluetoothLowEnergyState.poweredOn) {
        throw StateError('蓝牙未开启或未授权');
      }

      await _peripheralManager.removeAllServices();
      _deviceInfoCharacteristic = GATTCharacteristic.mutable(
        uuid: _deviceInfoCharUuid,
        properties: const [GATTCharacteristicProperty.read],
        permissions: const [GATTCharacteristicPermission.read],
        descriptors: const [],
      );
      final service = GATTService(
        uuid: _serviceUuid,
        isPrimary: true,
        includedServices: const [],
        characteristics: [_deviceInfoCharacteristic!],
      );
      await _peripheralManager.addService(service);
      await _readSubscription?.cancel();
      _readSubscription = _peripheralManager.characteristicReadRequested
          .listen(_handleReadRequest);

      await _peripheralManager.startAdvertising(
        Advertisement(
          name: Platform.isWindows ? null : 'Apilot',
          serviceUUIDs: [_serviceUuid],
          serviceData: Platform.isAndroid || Platform.isWindows
              ? {
                  _serviceUuid:
                      Uint8List.fromList(utf8.encode(localDevice.ipAddress))
                }
              : const {},
        ),
      );
      _isAdvertising = true;
      debugPrint('[BT] 已开始广播 Apilot 设备信息');
    } catch (e) {
      debugPrint('[BT] 开始广播失败: $e');
      rethrow;
    }
  }

  Future<void> _ensureAndroidBluetoothPermissions({
    bool includeAdvertise = false,
  }) async {
    if (!Platform.isAndroid) return;

    final permissions = androidPermissionPlanForSdk(
      sdkInt: androidSdkIntFromOperatingSystemVersion(
          Platform.operatingSystemVersion),
      includeAdvertise: includeAdvertise,
    );
    final statuses = await permissions.request();
    final denied = statuses.entries.where((entry) {
      final status = entry.value;
      return !(status.isGranted || status.isLimited);
    }).toList();

    if (denied.isNotEmpty) {
      throw StateError('需要开启附近设备/蓝牙权限后才能发现和广播 Apilot 设备');
    }
  }

  Future<List<DeviceInfo>> discoverApilotDevices({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_isScanning) return discoveredDevices;

    if (!await isAvailable()) {
      throw StateError('蓝牙未开启或未授权');
    }

    _isScanning = true;
    _discoveredDevices.clear();
    await _discoveredSubscription?.cancel();

    final completer = Completer<List<DeviceInfo>>();
    Timer? timer;
    _discoveredSubscription =
        _centralManager.discovered.listen((eventArgs) async {
      try {
        final device = await _readDeviceInfo(eventArgs);
        if (device == null) return;
        final index = _discoveredDevices.indexWhere(
          (existing) =>
              existing.id == device.id ||
              existing.ipAddress == device.ipAddress,
        );
        if (index >= 0) {
          _discoveredDevices[index] = device;
        } else {
          _discoveredDevices.add(device);
        }
      } catch (e) {
        debugPrint('[BT] 读取蓝牙设备信息失败: $e');
      }
    });

    try {
      await _centralManager.startDiscovery(serviceUUIDs: [_serviceUuid]);
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(discoveredDevices);
        }
      });
      return await completer.future;
    } finally {
      timer?.cancel();
      await stopScan();
    }
  }

  Future<DeviceInfo?> _readDeviceInfo(DiscoveredEventArgs eventArgs) async {
    try {
      final peripheral = eventArgs.peripheral;
      await _centralManager.connect(peripheral);
      try {
        final services = await _centralManager.discoverGATT(peripheral);
        final service =
            services.where((item) => item.uuid == _serviceUuid).firstOrNull;
        if (service == null) return null;
        final characteristic = service.characteristics
            .where((item) => item.uuid == _deviceInfoCharUuid)
            .firstOrNull;
        if (characteristic == null) return null;

        final bytes = await _centralManager.readCharacteristic(
            peripheral, characteristic);
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return DeviceInfo.fromJson(json);
      } finally {
        await _centralManager.disconnect(peripheral);
      }
    } catch (e) {
      debugPrint('[BT] 连接蓝牙外设失败: $e');
      return _deviceFromAdvertisement(eventArgs);
    }
  }

  DeviceInfo? _deviceFromAdvertisement(DiscoveredEventArgs eventArgs) {
    try {
      final serviceData = eventArgs.advertisement.serviceData[_serviceUuid];
      if (serviceData == null || serviceData.isEmpty) return null;
      final ip = utf8.decode(serviceData);
      if (ip.isEmpty) return null;
      return DeviceInfo(
        id: 'bt_${eventArgs.peripheral.uuid}',
        name: eventArgs.advertisement.name ?? 'Apilot 设备',
        platform: 'unknown',
        ipAddress: ip,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleReadRequest(
      GATTCharacteristicReadRequestedEventArgs eventArgs) async {
    final characteristic = _deviceInfoCharacteristic;
    final localDevice = _advertisedDevice;
    if (characteristic == null ||
        localDevice == null ||
        eventArgs.characteristic != characteristic) {
      await _peripheralManager.respondReadRequestWithError(
        eventArgs.request,
        error: GATTError.attributeNotFound,
      );
      return;
    }

    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode(localDevice.toJson())));
    final offset = eventArgs.request.offset;
    if (offset > bytes.length) {
      await _peripheralManager.respondReadRequestWithError(
        eventArgs.request,
        error: GATTError.invalidOffset,
      );
      return;
    }
    await _peripheralManager.respondReadRequestWithValue(
      eventArgs.request,
      value: bytes.sublist(offset),
    );
  }

  Future<void> stopScan() async {
    _isScanning = false;
    try {
      await _centralManager.stopDiscovery();
    } catch (_) {}
    await _discoveredSubscription?.cancel();
    _discoveredSubscription = null;
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _peripheralManager.stopAdvertising();
      await _peripheralManager.removeAllServices();
    } catch (e) {
      debugPrint('[BT] 停止广播失败: $e');
    }
    _isAdvertising = false;
  }

  void dispose() {
    stopScan();
    stopAdvertising();
    _readSubscription?.cancel();
  }
}
