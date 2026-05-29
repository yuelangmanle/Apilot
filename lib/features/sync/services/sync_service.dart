import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/models/api_config.dart';
import '../../../core/models/device_info.dart';
import '../../../core/services/database_service.dart';

class SyncService {
  static const int _discoveryPort = 45678;
  static const int _syncPort = 45679;
  static const String _magicHeader = 'API_MANAGER_SYNC';

  final List<DeviceInfo> _devices = [];
  HttpServer? _syncServer;
  RawDatagramSocket? _discoverySocket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  List<DeviceInfo> get discoveredDevices => List.unmodifiable(_devices);
  bool get isRunning => _isRunning;

  Future<DeviceInfo> getLocalDeviceInfo() async {
    final hostname = Platform.localHostname;
    final platform = _getPlatformName();
    final ip = await _getLocalIP();

    return DeviceInfo(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      name: hostname,
      platform: platform,
      ipAddress: ip,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
  }

  String _getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  Future<String> _getLocalIP() async {
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _startDiscovery();
    await _startSyncServer();
  }

  Future<void> stop() async {
    _isRunning = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _syncServer?.close();
    _syncServer = null;
    _devices.clear();
  }

  Future<void> _startDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;

      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) _handleDiscoveryMessage(datagram);
        }
      });

      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => _broadcastPresence());
      _broadcastPresence();
    } catch (e) {
      // UDP discovery not available
    }
  }

  void _broadcastPresence() async {
    try {
      final device = await getLocalDeviceInfo();
      final message = jsonEncode({'header': _magicHeader, 'device': device.toJson()});
      _discoverySocket?.send(message.codeUnits, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (_) {}
  }

  void _handleDiscoveryMessage(Datagram datagram) {
    try {
      final message = jsonDecode(String.fromCharCodes(datagram.data));
      if (message['header'] != _magicHeader) return;

      final device = DeviceInfo.fromJson(message['device'] as Map<String, dynamic>);
      final localIP = _discoverySocket?.address.address;
      if (device.ipAddress == localIP) return;

      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        _devices[index] = device;
      } else {
        _devices.add(device);
      }
    } catch (_) {}
  }

  Future<void> _startSyncServer() async {
    try {
      _syncServer = await HttpServer.bind(InternetAddress.anyIPv4, _syncPort);

      _syncServer!.listen((request) async {
        if (request.method == 'POST' && request.uri.path == '/sync') {
          await _handleSyncRequest(request);
        } else if (request.method == 'GET' && request.uri.path == '/configs') {
          await _handleGetConfigs(request);
        } else if (request.method == 'GET' && request.uri.path == '/ping') {
          request.response..statusCode = HttpStatus.ok..write('pong')..close();
        } else {
          request.response..statusCode = HttpStatus.notFound..close();
        }
      });
    } catch (e) {
      // Server start failed
    }
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final configs = parseSyncPayload(data);

      // Save received configs
      final dbService = DatabaseService();
      await dbService.initialize();
      for (final config in configs) {
        await dbService.insertApiConfig(config);
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'received': configs.length}))
        ..close();
    } catch (e) {
      request.response..statusCode = HttpStatus.badRequest..close();
    }
  }

  Future<void> _handleGetConfigs(HttpRequest request) async {
    try {
      final dbService = DatabaseService();
      await dbService.initialize();
      final configs = await dbService.getAllApiConfigs();

      final payload = createSyncPayload(configs);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload))
        ..close();
    } catch (e) {
      request.response..statusCode = HttpStatus.internalServerError..close();
    }
  }

  Future<bool> sendConfigs(DeviceInfo device, List<ApiConfig> configs) async {
    try {
      final payload = createSyncPayload(configs);
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://${device.ipAddress}:$_syncPort/sync'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));

      final response = await request.close();
      client.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      return false;
    }
  }

  Future<List<ApiConfig>> receiveConfigs(DeviceInfo device) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://${device.ipAddress}:$_syncPort/configs'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      return parseSyncPayload(data);
    } catch (e) {
      return [];
    }
  }

  static Map<String, dynamic> createSyncPayload(List<ApiConfig> configs) {
    return {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'configs': configs.map((c) => c.toJson()).toList(),
    };
  }

  static List<ApiConfig> parseSyncPayload(Map<String, dynamic> data) {
    final configs = data['configs'] as List;
    return configs.map((c) => ApiConfig.fromJson(c as Map<String, dynamic>)).toList();
  }
}
