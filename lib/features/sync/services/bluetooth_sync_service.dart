import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/device_info.dart';
import 'bluetooth_transfer_protocol.dart';

enum BluetoothTransferOperation {
  push,
  pull,
}

extension on BluetoothTransferOperation {
  String get wireName => name;
}

BluetoothTransferOperation _parseTransferOperation(Object? value) {
  return BluetoothTransferOperation.values.firstWhere(
    (operation) => operation.wireName == value,
    orElse: () => throw const FormatException('未知蓝牙传输操作'),
  );
}

class BluetoothIncomingTransferOffer {
  final String sessionId;
  final BluetoothTransferOperation operation;
  final String senderName;
  final int configCount;
  final int payloadBytes;

  const BluetoothIncomingTransferOffer({
    required this.sessionId,
    required this.operation,
    required this.senderName,
    required this.configCount,
    required this.payloadBytes,
  });
}

class BluetoothReceivedTransfer {
  final String sessionId;
  final Uint8List payload;
  final int configCount;

  const BluetoothReceivedTransfer({
    required this.sessionId,
    required this.payload,
    required this.configCount,
  });
}

class BluetoothTransferResult {
  final bool success;
  final String message;

  const BluetoothTransferResult({required this.success, required this.message});
}

/// Manages direct BLE GATT discovery and configuration transfer.
///
/// Discovery only exposes device metadata. API configuration payloads are
/// transferred after both devices explicitly approve the operation, using a
/// framed, checksummed characteristic rather than the WiFi sync server.
class BluetoothSyncService {
  static final UUID _serviceUuid =
      UUID.fromString('12345678-1234-1234-1234-123456789abc');
  static final UUID _deviceInfoCharUuid =
      UUID.fromString('12345678-1234-1234-1234-123456789abd');
  static final UUID _transferCharUuid =
      UUID.fromString('12345678-1234-1234-1234-123456789abe');
  static const _transferTimeout = Duration(seconds: 75);

  final CentralManager _centralManager = CentralManager();
  final PeripheralManager _peripheralManager = PeripheralManager();
  final List<DeviceInfo> _discoveredDevices = [];
  final Map<String, Peripheral> _peripheralsByDeviceId = {};
  final Map<String, BluetoothFrameDecoder> _incomingDecoders = {};
  final Map<String, _InboundTransferSession> _inboundSessions = {};
  final StreamController<BluetoothIncomingTransferOffer> _incomingOffers =
      StreamController.broadcast();
  final StreamController<BluetoothReceivedTransfer> _receivedTransfers =
      StreamController.broadcast();

  StreamSubscription<DiscoveredEventArgs>? _discoveredSubscription;
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>?
      _readSubscription;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>?
      _writeSubscription;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>?
      _notificationSubscription;
  final Set<String> _readingPeripherals = {};
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _disposed = false;
  DeviceInfo? _advertisedDevice;
  GATTCharacteristic? _deviceInfoCharacteristic;
  GATTCharacteristic? _transferCharacteristic;
  _CentralTransferSession? _activeCentralSession;

  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  List<DeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  Stream<BluetoothIncomingTransferOffer> get incomingOffers =>
      _incomingOffers.stream;
  Stream<BluetoothReceivedTransfer> get receivedTransfers =>
      _receivedTransfers.stream;

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
      var state = await _waitForKnownState(
        readState: () => _centralManager.state,
        stateChanges: _centralManager.stateChanged,
      );
      if (state == BluetoothLowEnergyState.poweredOn) return true;
      if (state == BluetoothLowEnergyState.unauthorized && Platform.isAndroid) {
        if (!await _centralManager.authorize()) return false;
        state = await _waitForPoweredOn(
          readState: () => _centralManager.state,
          stateChanges: _centralManager.stateChanged,
        );
      }
      return state == BluetoothLowEnergyState.poweredOn;
    } catch (error) {
      debugPrint('[BT] 蓝牙状态检查失败: $error');
      return false;
    }
  }

  Future<void> startAdvertising(DeviceInfo localDevice) async {
    _advertisedDevice = localDevice;
    if (_isAdvertising) return;

    try {
      await _ensureAndroidBluetoothPermissions(includeAdvertise: true);
      var state = await _waitForKnownState(
        readState: () => _peripheralManager.state,
        stateChanges: _peripheralManager.stateChanged,
      );
      if (state == BluetoothLowEnergyState.unauthorized && Platform.isAndroid) {
        if (!await _peripheralManager.authorize()) {
          throw StateError('蓝牙权限未授予');
        }
        state = await _waitForPoweredOn(
          readState: () => _peripheralManager.state,
          stateChanges: _peripheralManager.stateChanged,
        );
      }
      if (state != BluetoothLowEnergyState.poweredOn) {
        throw StateError('蓝牙未开启或未授权');
      }

      await _peripheralManager.removeAllServices();
      _deviceInfoCharacteristic = GATTCharacteristic.mutable(
        uuid: _deviceInfoCharUuid,
        properties: const [GATTCharacteristicProperty.read],
        permissions: const [GATTCharacteristicPermission.read],
        descriptors: const [],
      );
      _transferCharacteristic = GATTCharacteristic.mutable(
        uuid: _transferCharUuid,
        properties: const [
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.indicate,
        ],
        permissions: const [GATTCharacteristicPermission.write],
        descriptors: const [],
      );
      final service = GATTService(
        uuid: _serviceUuid,
        isPrimary: true,
        includedServices: const [],
        characteristics: [_deviceInfoCharacteristic!, _transferCharacteristic!],
      );
      await _peripheralManager.addService(service);
      await _subscribePeripheralEvents();
      await _peripheralManager.startAdvertising(
        Advertisement(
          name: Platform.isWindows ? null : 'Apilot',
          serviceUUIDs: [_serviceUuid],
        ),
      );
      _isAdvertising = true;
      debugPrint('[BT] 已开始广播 Apilot GATT 服务');
    } catch (error) {
      debugPrint('[BT] 开始广播失败: $error');
      rethrow;
    }
  }

  Future<void> _subscribePeripheralEvents() async {
    await _readSubscription?.cancel();
    await _writeSubscription?.cancel();
    _readSubscription = _peripheralManager.characteristicReadRequested
        .listen(_handleReadRequest);
    _writeSubscription = _peripheralManager.characteristicWriteRequested
        .listen((event) => unawaited(_handleWriteRequest(event)));
    _notificationSubscription ??= _centralManager.characteristicNotified
        .listen((event) => unawaited(_handleNotification(event)));
  }

  Future<void> _ensureAndroidBluetoothPermissions({
    bool includeAdvertise = false,
  }) async {
    if (!Platform.isAndroid) return;

    final permissions = androidPermissionPlanForSdk(
      sdkInt: androidSdkIntFromOperatingSystemVersion(
        Platform.operatingSystemVersion,
      ),
      includeAdvertise: includeAdvertise,
    );
    final statuses = await permissions.request();
    final denied = statuses.entries.where((entry) {
      final status = entry.value;
      return !(status.isGranted || status.isLimited);
    }).toList();

    if (denied.isNotEmpty) {
      throw StateError('需要开启附近设备/蓝牙权限后才能发现和传输 Apilot 配置');
    }
  }

  Future<BluetoothLowEnergyState> _waitForKnownState({
    required BluetoothLowEnergyState Function() readState,
    required Stream<BluetoothLowEnergyStateChangedEventArgs> stateChanges,
  }) async {
    final currentState = readState();
    if (currentState != BluetoothLowEnergyState.unknown) return currentState;
    try {
      return await stateChanges
          .map((event) => event.state)
          .firstWhere((state) => state != BluetoothLowEnergyState.unknown)
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return readState();
    }
  }

  Future<BluetoothLowEnergyState> _waitForPoweredOn({
    required BluetoothLowEnergyState Function() readState,
    required Stream<BluetoothLowEnergyStateChangedEventArgs> stateChanges,
  }) async {
    if (readState() == BluetoothLowEnergyState.poweredOn) {
      return BluetoothLowEnergyState.poweredOn;
    }
    try {
      return await stateChanges
          .map((event) => event.state)
          .firstWhere((state) => state == BluetoothLowEnergyState.poweredOn)
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return readState();
    }
  }

  Future<List<DeviceInfo>> discoverApilotDevices({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_isScanning) return discoveredDevices;
    if (!await isAvailable()) throw StateError('蓝牙未开启或未授权');

    _isScanning = true;
    _discoveredDevices.clear();
    _peripheralsByDeviceId.clear();
    await _discoveredSubscription?.cancel();

    final completer = Completer<List<DeviceInfo>>();
    Timer? timer;
    _discoveredSubscription = _centralManager.discovered.listen((event) async {
      final peripheralId = event.peripheral.uuid.toString();
      if (!_readingPeripherals.add(peripheralId)) return;
      try {
        final device = await _readDeviceInfo(event);
        if (device == null || device.id == _advertisedDevice?.id) return;
        _peripheralsByDeviceId[device.id] = event.peripheral;
        final index = _discoveredDevices.indexWhere((existing) =>
            existing.id == device.id ||
            existing.ipAddress == device.ipAddress &&
                device.ipAddress != '蓝牙近场');
        if (index >= 0) {
          _discoveredDevices[index] = device;
        } else {
          _discoveredDevices.add(device);
        }
      } catch (error) {
        debugPrint('[BT] 读取蓝牙设备信息失败: $error');
      } finally {
        _readingPeripherals.remove(peripheralId);
      }
    });

    try {
      await _centralManager.startDiscovery(serviceUUIDs: [_serviceUuid]);
      timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(discoveredDevices);
      });
      return await completer.future;
    } finally {
      timer?.cancel();
      await stopScan();
    }
  }

  Future<DeviceInfo?> _readDeviceInfo(DiscoveredEventArgs event) async {
    try {
      final peripheral = event.peripheral;
      await _centralManager.connect(peripheral);
      try {
        final services = await _centralManager.discoverGATT(peripheral);
        final service = _findService(services, _serviceUuid);
        final characteristic = service == null
            ? null
            : _findCharacteristic(service, _deviceInfoCharUuid);
        if (characteristic == null) return _deviceFromAdvertisement(event);
        final bytes = await _centralManager.readCharacteristic(
            peripheral, characteristic);
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) return _deviceFromAdvertisement(event);
        return DeviceInfo.fromJson(Map<String, dynamic>.from(decoded));
      } finally {
        await _centralManager.disconnect(peripheral);
      }
    } catch (_) {
      return _deviceFromAdvertisement(event);
    }
  }

  GATTService? _findService(List<GATTService> services, UUID uuid) {
    for (final service in services) {
      if (service.uuid == uuid) return service;
    }
    return null;
  }

  GATTCharacteristic? _findCharacteristic(GATTService service, UUID uuid) {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == uuid) return characteristic;
    }
    return null;
  }

  DeviceInfo _deviceFromAdvertisement(DiscoveredEventArgs event) {
    return DeviceInfo(
      id: 'bt_${event.peripheral.uuid}',
      name: event.advertisement.name ?? 'Apilot 设备',
      platform: 'unknown',
      ipAddress: '蓝牙近场',
    );
  }

  Future<void> _handleReadRequest(
    GATTCharacteristicReadRequestedEventArgs event,
  ) async {
    final characteristic = _deviceInfoCharacteristic;
    final localDevice = _advertisedDevice;
    if (characteristic == null ||
        localDevice == null ||
        event.characteristic != characteristic) {
      await _peripheralManager.respondReadRequestWithError(
        event.request,
        error: GATTError.attributeNotFound,
      );
      return;
    }

    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode(localDevice.toJson())));
    final offset = event.request.offset;
    if (offset > bytes.length) {
      await _peripheralManager.respondReadRequestWithError(
        event.request,
        error: GATTError.invalidOffset,
      );
      return;
    }
    await _peripheralManager.respondReadRequestWithValue(
      event.request,
      value: bytes.sublist(offset),
    );
  }

  Future<void> _handleWriteRequest(
    GATTCharacteristicWriteRequestedEventArgs event,
  ) async {
    if (event.characteristic != _transferCharacteristic) {
      await _peripheralManager.respondWriteRequestWithError(
        event.request,
        error: GATTError.attributeNotFound,
      );
      return;
    }

    final centralId = event.central.uuid.toString();
    late final List<BluetoothTransferFrame> frames;
    try {
      final decoder = _incomingDecoders.putIfAbsent(
        centralId,
        BluetoothFrameDecoder.new,
      );
      frames = decoder.add(event.request.value);
    } on FormatException catch (error) {
      await _peripheralManager.respondWriteRequestWithError(
        event.request,
        error: GATTError.invalidPDU,
      );
      await _notifyError(event.central, '蓝牙传输帧无效：${error.message}');
      return;
    } catch (error) {
      await _peripheralManager.respondWriteRequestWithError(
        event.request,
        error: GATTError.unlikelyError,
      );
      await _notifyError(event.central, '蓝牙传输失败，请重新尝试');
      debugPrint('[BT] 处理蓝牙传输帧失败: $error');
      return;
    }

    await _peripheralManager.respondWriteRequest(event.request);
    for (final frame in frames) {
      try {
        await _handleFrameFromCentral(event.central, frame);
      } catch (error) {
        await _notifyError(event.central, '蓝牙传输失败，请重新尝试', frame.sessionId);
        debugPrint('[BT] 处理已确认的蓝牙传输帧失败: $error');
      }
    }
  }

  Future<void> _handleFrameFromCentral(
    Central central,
    BluetoothTransferFrame frame,
  ) async {
    final key = _inboundKey(central, frame.sessionId);
    switch (frame.type) {
      case BluetoothTransferFrameType.offer:
        if (_inboundSessions.containsKey(key)) {
          await _notifyError(central, '该蓝牙传输会话已存在', frame.sessionId);
          return;
        }
        final operation = _parseTransferOperation(frame.data['operation']);
        final configCount = _readNonNegativeInt(frame.data['configCount']);
        final payloadBytes = _readNonNegativeInt(frame.data['payloadBytes']);
        if (payloadBytes > BluetoothTransferProtocol.maxTransferBytes) {
          await _notifyError(central, '配置内容超过蓝牙传输上限', frame.sessionId);
          return;
        }
        final senderName = frame.data['senderName'] is String
            ? frame.data['senderName'] as String
            : '附近设备';
        _inboundSessions[key] = _InboundTransferSession(
          central: central,
          sessionId: frame.sessionId,
          operation: operation,
          configCount: configCount,
          payloadBytes: payloadBytes,
          payloadAssembler: operation == BluetoothTransferOperation.push
              ? BluetoothPayloadAssembler(sessionId: frame.sessionId)
              : null,
        );
        _incomingOffers.add(BluetoothIncomingTransferOffer(
          sessionId: frame.sessionId,
          operation: operation,
          senderName: senderName,
          configCount: configCount,
          payloadBytes: payloadBytes,
        ));
        return;
      case BluetoothTransferFrameType.payload:
        final session = _inboundSessions[key];
        if (session == null ||
            !session.accepted ||
            session.operation != BluetoothTransferOperation.push ||
            session.payloadAssembler == null) {
          await _notifyError(central, '蓝牙传输尚未获准', frame.sessionId);
          return;
        }
        session.payloadAssembler!.add(frame);
        return;
      case BluetoothTransferFrameType.complete:
        final session = _inboundSessions[key];
        if (session == null ||
            !session.accepted ||
            session.operation != BluetoothTransferOperation.push ||
            session.payloadAssembler == null) {
          await _notifyError(central, '蓝牙传输状态无效', frame.sessionId);
          return;
        }
        final payload = session.payloadAssembler!.build();
        _receivedTransfers.add(BluetoothReceivedTransfer(
          sessionId: frame.sessionId,
          payload: payload,
          configCount: session.configCount,
        ));
        return;
      case BluetoothTransferFrameType.result:
        _inboundSessions.remove(key);
        return;
      case BluetoothTransferFrameType.accepted:
      case BluetoothTransferFrameType.rejected:
      case BluetoothTransferFrameType.error:
        await _notifyError(central, '蓝牙传输帧方向错误', frame.sessionId);
        return;
    }
  }

  int _readNonNegativeInt(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('蓝牙传输元数据无效');
    }
    return value;
  }

  String _inboundKey(Central central, String sessionId) =>
      '${central.uuid}:$sessionId';

  _InboundTransferSession? _findInboundSession(String sessionId) {
    for (final entry in _inboundSessions.entries) {
      if (entry.value.sessionId == sessionId) return entry.value;
    }
    return null;
  }

  Future<void> acceptIncomingTransfer(
    String sessionId, {
    Uint8List? payload,
  }) async {
    final session = _findInboundSession(sessionId);
    if (session == null) throw StateError('蓝牙传输请求已失效');
    if (session.accepted) return;
    if (session.operation == BluetoothTransferOperation.pull &&
        payload == null) {
      throw ArgumentError('接收方请求配置时必须提供本机配置内容');
    }
    if (payload != null &&
        payload.length > BluetoothTransferProtocol.maxTransferBytes) {
      throw ArgumentError('配置内容超过 1 MiB，无法通过蓝牙传输');
    }

    session.accepted = true;
    await _notifyFrame(
      session.central,
      BluetoothTransferFrame(
        type: BluetoothTransferFrameType.accepted,
        sessionId: sessionId,
      ),
    );
    if (session.operation != BluetoothTransferOperation.pull) return;

    final frames = BluetoothTransferProtocol.createPayloadFrames(
      sessionId: sessionId,
      payload: payload!,
    );
    for (final frame in frames) {
      await _notifyFrame(session.central, frame);
    }
    await _notifyFrame(
      session.central,
      BluetoothTransferFrame(
        type: BluetoothTransferFrameType.complete,
        sessionId: sessionId,
      ),
    );
  }

  Future<void> rejectIncomingTransfer(String sessionId,
      {String? reason}) async {
    final session = _findInboundSession(sessionId);
    if (session == null) return;
    _inboundSessions.remove(_inboundKey(session.central, sessionId));
    await _notifyFrame(
      session.central,
      BluetoothTransferFrame(
        type: BluetoothTransferFrameType.rejected,
        sessionId: sessionId,
        data: {'message': reason ?? '对方拒绝了蓝牙传输请求'},
      ),
    );
  }

  Future<void> completeIncomingTransfer(
    String sessionId, {
    required bool success,
    required String message,
  }) async {
    final session = _findInboundSession(sessionId);
    if (session == null) return;
    _inboundSessions.remove(_inboundKey(session.central, sessionId));
    await _notifyFrame(
      session.central,
      BluetoothTransferFrame(
        type: BluetoothTransferFrameType.result,
        sessionId: sessionId,
        data: {'success': success, 'message': message},
      ),
    );
  }

  Future<BluetoothTransferResult> sendPayload({
    required DeviceInfo device,
    required Uint8List payload,
    required int configCount,
  }) async {
    return _runOutgoingTransfer(
      device: device,
      operation: BluetoothTransferOperation.push,
      payload: payload,
      configCount: configCount,
    ).then((value) => value.result!);
  }

  Future<Uint8List> requestPayload({required DeviceInfo device}) async {
    final outcome = await _runOutgoingTransfer(
      device: device,
      operation: BluetoothTransferOperation.pull,
      payload: null,
      configCount: 0,
    );
    return outcome.payload!;
  }

  Future<_OutgoingTransferOutcome> _runOutgoingTransfer({
    required DeviceInfo device,
    required BluetoothTransferOperation operation,
    required Uint8List? payload,
    required int configCount,
  }) async {
    if (_activeCentralSession != null) {
      throw StateError('已有蓝牙传输正在进行');
    }
    final peripheral = _peripheralsByDeviceId[device.id];
    if (peripheral == null) {
      throw StateError('蓝牙设备信息已过期，请先重新发现附近设备');
    }
    if (payload != null &&
        payload.length > BluetoothTransferProtocol.maxTransferBytes) {
      throw ArgumentError('配置内容超过 1 MiB，无法通过蓝牙传输');
    }

    final sessionId = const Uuid().v4();
    final session = _CentralTransferSession(
      peripheral: peripheral,
      sessionId: sessionId,
      operation: operation,
    );
    _activeCentralSession = session;
    GATTCharacteristic? characteristic;
    try {
      await _centralManager.connect(peripheral);
      if (Platform.isAndroid) {
        try {
          await _centralManager.requestMTU(peripheral, mtu: 247);
        } catch (_) {}
      }
      final services = await _centralManager.discoverGATT(peripheral);
      final service = _findService(services, _serviceUuid);
      characteristic = service == null
          ? null
          : _findCharacteristic(service, _transferCharUuid);
      if (characteristic == null) {
        throw StateError('对方版本不支持真实蓝牙传输，请升级后重新发现');
      }
      session.characteristic = characteristic;
      _notificationSubscription ??= _centralManager.characteristicNotified
          .listen((event) => unawaited(_handleNotification(event)));
      await _centralManager.setCharacteristicNotifyState(
        peripheral,
        characteristic,
        state: true,
      );

      await _writeFrame(
        session,
        BluetoothTransferFrame(
          type: BluetoothTransferFrameType.offer,
          sessionId: sessionId,
          data: {
            'operation': operation.wireName,
            'senderName': _advertisedDevice?.name ?? 'Apilot 设备',
            'configCount': configCount,
            'payloadBytes': payload?.length ?? 0,
          },
        ),
      );
      await session.accepted.future.timeout(_transferTimeout);

      if (operation == BluetoothTransferOperation.push) {
        final frames = BluetoothTransferProtocol.createPayloadFrames(
          sessionId: sessionId,
          payload: payload!,
        );
        for (final frame in frames) {
          await _writeFrame(session, frame);
        }
        await _writeFrame(
          session,
          BluetoothTransferFrame(
            type: BluetoothTransferFrameType.complete,
            sessionId: sessionId,
          ),
        );
        final result = await session.result.future.timeout(_transferTimeout);
        return _OutgoingTransferOutcome(result: result);
      }

      final received = await session.payload.future.timeout(_transferTimeout);
      await _writeFrame(
        session,
        BluetoothTransferFrame(
          type: BluetoothTransferFrameType.result,
          sessionId: sessionId,
          data: const {'success': true, 'message': '已收到蓝牙配置'},
        ),
      );
      return _OutgoingTransferOutcome(payload: received);
    } finally {
      if (characteristic != null) {
        try {
          await _centralManager.setCharacteristicNotifyState(
            peripheral,
            characteristic,
            state: false,
          );
        } catch (_) {}
      }
      try {
        await _centralManager.disconnect(peripheral);
      } catch (_) {}
      if (identical(_activeCentralSession, session)) {
        _activeCentralSession = null;
      }
    }
  }

  Future<void> _writeFrame(
    _CentralTransferSession session,
    BluetoothTransferFrame frame,
  ) async {
    final characteristic = session.characteristic;
    if (characteristic == null) throw StateError('蓝牙传输特征未就绪');
    final encoded = BluetoothTransferProtocol.encodeFrame(frame);
    final maxLength = await _centralManager.getMaximumWriteLength(
      session.peripheral,
      type: GATTCharacteristicWriteType.withResponse,
    );
    for (var offset = 0; offset < encoded.length; offset += maxLength) {
      final end = (offset + maxLength).clamp(0, encoded.length);
      await _centralManager.writeCharacteristic(
        session.peripheral,
        characteristic,
        value: encoded.sublist(offset, end),
        type: GATTCharacteristicWriteType.withResponse,
      );
    }
  }

  Future<void> _handleNotification(
    GATTCharacteristicNotifiedEventArgs event,
  ) async {
    final session = _activeCentralSession;
    if (session == null ||
        event.peripheral != session.peripheral ||
        event.characteristic.uuid != _transferCharUuid) {
      return;
    }
    try {
      for (final frame in session.decoder.add(event.value)) {
        if (frame.sessionId != session.sessionId) {
          continue;
        }
        switch (frame.type) {
          case BluetoothTransferFrameType.accepted:
            if (!session.accepted.isCompleted) session.accepted.complete();
            break;
          case BluetoothTransferFrameType.rejected:
          case BluetoothTransferFrameType.error:
            final message = frame.data['message'] is String
                ? frame.data['message'] as String
                : '对方拒绝或中止了蓝牙传输';
            final error = StateError(message);
            if (!session.accepted.isCompleted) {
              session.accepted.completeError(error);
            }
            if (!session.result.isCompleted) {
              session.result.completeError(error);
            }
            if (!session.payload.isCompleted) {
              session.payload.completeError(error);
            }
            break;
          case BluetoothTransferFrameType.payload:
            session.payloadAssembler ??=
                BluetoothPayloadAssembler(sessionId: session.sessionId);
            session.payloadAssembler!.add(frame);
            break;
          case BluetoothTransferFrameType.complete:
            final assembler = session.payloadAssembler;
            if (assembler == null) {
              throw const FormatException('缺少蓝牙传输内容');
            }
            if (!session.payload.isCompleted) {
              session.payload.complete(assembler.build());
            }
            break;
          case BluetoothTransferFrameType.result:
            if (!session.result.isCompleted) {
              final success = frame.data['success'] == true;
              final message = frame.data['message'] is String
                  ? frame.data['message'] as String
                  : success
                      ? '蓝牙传输完成'
                      : '对方未能保存蓝牙配置';
              session.result.complete(
                BluetoothTransferResult(success: success, message: message),
              );
            }
            break;
          case BluetoothTransferFrameType.offer:
            throw const FormatException('收到方向错误的蓝牙传输帧');
        }
      }
    } catch (error, stackTrace) {
      if (!session.accepted.isCompleted) {
        session.accepted.completeError(error, stackTrace);
      }
      if (!session.result.isCompleted) {
        session.result.completeError(error, stackTrace);
      }
      if (!session.payload.isCompleted) {
        session.payload.completeError(error, stackTrace);
      }
    }
  }

  Future<void> _notifyFrame(
      Central central, BluetoothTransferFrame frame) async {
    final characteristic = _transferCharacteristic;
    if (characteristic == null) throw StateError('蓝牙传输服务未启动');
    final encoded = BluetoothTransferProtocol.encodeFrame(frame);
    final maxLength = await _peripheralManager.getMaximumNotifyLength(central);
    for (var offset = 0; offset < encoded.length; offset += maxLength) {
      final end = (offset + maxLength).clamp(0, encoded.length);
      await _peripheralManager.notifyCharacteristic(
        central,
        characteristic,
        value: encoded.sublist(offset, end),
      );
    }
  }

  Future<void> _notifyError(Central central, String message,
      [String? sessionId]) {
    return _notifyFrame(
      central,
      BluetoothTransferFrame(
        type: BluetoothTransferFrameType.error,
        sessionId: sessionId ?? const Uuid().v4(),
        data: {'message': message},
      ),
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
    } catch (error) {
      debugPrint('[BT] 停止广播失败: $error');
    }
    _isAdvertising = false;
    _transferCharacteristic = null;
    _deviceInfoCharacteristic = null;
    _inboundSessions.clear();
    _incomingDecoders.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stopScan());
    unawaited(stopAdvertising());
    unawaited(_readSubscription?.cancel() ?? Future<void>.value());
    unawaited(_writeSubscription?.cancel() ?? Future<void>.value());
    unawaited(_notificationSubscription?.cancel() ?? Future<void>.value());
    unawaited(_incomingOffers.close());
    unawaited(_receivedTransfers.close());
  }
}

class _InboundTransferSession {
  final Central central;
  final String sessionId;
  final BluetoothTransferOperation operation;
  final int configCount;
  final int payloadBytes;
  final BluetoothPayloadAssembler? payloadAssembler;
  bool accepted = false;

  _InboundTransferSession({
    required this.central,
    required this.sessionId,
    required this.operation,
    required this.configCount,
    required this.payloadBytes,
    required this.payloadAssembler,
  });
}

class _CentralTransferSession {
  final Peripheral peripheral;
  final String sessionId;
  final BluetoothTransferOperation operation;
  final BluetoothFrameDecoder decoder = BluetoothFrameDecoder();
  final Completer<void> accepted = Completer<void>();
  final Completer<BluetoothTransferResult> result =
      Completer<BluetoothTransferResult>();
  final Completer<Uint8List> payload = Completer<Uint8List>();
  GATTCharacteristic? characteristic;
  BluetoothPayloadAssembler? payloadAssembler;

  _CentralTransferSession({
    required this.peripheral,
    required this.sessionId,
    required this.operation,
  });
}

class _OutgoingTransferOutcome {
  final BluetoothTransferResult? result;
  final Uint8List? payload;

  const _OutgoingTransferOutcome({this.result, this.payload});
}
