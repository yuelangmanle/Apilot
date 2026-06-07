import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/device_info.dart';
import '../../../core/services/database_service.dart';

class SyncService {
  static const int _discoveryPort = 45678;
  static const int _syncPort = 45679;
  static const String _magicHeader = 'API_MANAGER_SYNC';
  static const String _multicastGroup = '224.0.0.1';
  static const String _deviceIdPrefsKey = 'apilot_sync_device_id';

  final List<DeviceInfo> _devices = [];
  final String? _localDeviceIdOverride;
  HttpServer? _syncServer;
  RawDatagramSocket? _discoverySocket;
  Timer? _broadcastTimer;
  bool _isRunning = false;
  String? _localDeviceIdCache;

  List<DeviceInfo> get discoveredDevices => List.unmodifiable(_devices);
  bool get isRunning => _isRunning;

  SyncService({String? localDeviceIdOverride})
      : _localDeviceIdOverride = localDeviceIdOverride;

  Future<DeviceInfo> getLocalDeviceInfo() async {
    final hostname = Platform.localHostname;
    final platform = _getPlatformName();
    final ip = await _getLocalIP();

    return DeviceInfo(
      id: await _getLocalDeviceId(),
      name: hostname,
      platform: platform,
      ipAddress: ip,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
  }

  Future<String> _getLocalDeviceId() async {
    final override = _localDeviceIdOverride;
    if (override != null) return override;
    if (_localDeviceIdCache != null) return _localDeviceIdCache!;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_deviceIdPrefsKey);
    if (saved != null && saved.isNotEmpty) {
      _localDeviceIdCache = saved;
      return saved;
    }

    final generated = 'apilot_${const Uuid().v4()}';
    await prefs.setString(_deviceIdPrefsKey, generated);
    _localDeviceIdCache = generated;
    return generated;
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
    } catch (e) {
      debugPrint('获取本机IP失败: $e');
    }
    return '127.0.0.1';
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    debugPrint('[Sync] 启动同步服务...');
    await _startDiscovery();
    await _startSyncServer();
    debugPrint('[Sync] 同步服务已启动，IP: ${await _getLocalIP()}');
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
    debugPrint('[Sync] 同步服务已停止');
  }

  Future<void> _startDiscovery() async {
    try {
      // 绑定到所有接口的发现端口
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;

      // 加入多播组（局域网内所有设备都能收到）
      try {
        _discoverySocket!.joinMulticast(InternetAddress(_multicastGroup));
        debugPrint('[Sync] 已加入多播组 $_multicastGroup');
      } catch (e) {
        debugPrint('[Sync] 加入多播组失败: $e，使用广播模式');
      }

      // 监听其他设备的广播
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) _handleDiscoveryMessage(datagram);
        }
      });

      // 定期广播自己的存在
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => _broadcastPresence());
      _broadcastPresence(); // 立即广播一次
      debugPrint('[Sync] UDP发现已启动，端口: $_discoveryPort');
    } catch (e) {
      debugPrint('[Sync] UDP发现启动失败: $e');
    }
  }

  void _broadcastPresence() async {
    try {
      final device = await getLocalDeviceInfo();
      final message = jsonEncode({'header': _magicHeader, 'device': device.toJson()});
      final data = message.codeUnits;

      // 同时发送到多播组和广播地址
      try {
        _discoverySocket?.send(data, InternetAddress(_multicastGroup), _discoveryPort);
      } catch (_) {}
      try {
        _discoverySocket?.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
      } catch (_) {}
    } catch (e) {
      debugPrint('[Sync] 广播失败: $e');
    }
  }

  void _handleDiscoveryMessage(Datagram datagram) async {
    try {
      final message = jsonDecode(String.fromCharCodes(datagram.data));
      if (message['header'] != _magicHeader) return;

      final device = DeviceInfo.fromJson(message['device'] as Map<String, dynamic>);
      await upsertDiscoveredDevice(device, sourceIp: datagram.address.address);
    } catch (e) {
      debugPrint('[Sync] 解析发现消息失败: $e');
    }
  }

  Future<bool> upsertDiscoveredDevice(
    DeviceInfo device, {
    String? sourceIp,
  }) async {
    if (await _isLocalDevice(device, sourceIp: sourceIp)) return false;

    final normalized = DeviceInfo(
      id: device.id,
      name: device.name.isEmpty ? '未知设备' : device.name,
      platform: device.platform,
      ipAddress: sourceIp != null && _isUsableRemoteIP(sourceIp) ? sourceIp : device.ipAddress,
      lastSeen: DateTime.now(),
      isOnline: true,
    );

    final index = _devices.indexWhere((existing) {
      if (existing.id == normalized.id) return true;
      return existing.ipAddress == normalized.ipAddress && normalized.ipAddress.isNotEmpty;
    });

    if (index >= 0) {
      _devices[index] = normalized;
    } else {
      _devices.add(normalized);
      debugPrint('[Sync] 发现设备: ${normalized.name} (${normalized.ipAddress})');
    }
    _devices.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return true;
  }

  Future<bool> _isLocalDevice(DeviceInfo device, {String? sourceIp}) async {
    final localDeviceId = await _getLocalDeviceId();
    if (device.id == localDeviceId) return true;

    final localIPs = await _getLocalIPv4Addresses();
    if (localIPs.contains(device.ipAddress)) return true;
    if (sourceIp != null && localIPs.contains(sourceIp)) return true;

    final socketAddress = _discoverySocket?.address.address;
    if (socketAddress != null && socketAddress != '0.0.0.0') {
      if (device.ipAddress == socketAddress || sourceIp == socketAddress) return true;
    }

    return false;
  }

  bool _isUsableRemoteIP(String ip) {
    return ip.isNotEmpty && ip != '0.0.0.0' && ip != '127.0.0.1';
  }

  Future<Set<String>> _getLocalIPv4Addresses() async {
    final addresses = <String>{'127.0.0.1'};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in interface.addresses) {
          addresses.add(addr.address);
        }
      }
    } catch (e) {
      debugPrint('[Sync] 获取本机IP列表失败: $e');
    }
    return addresses;
  }

  Future<void> _startSyncServer() async {
    try {
      _syncServer = await HttpServer.bind(InternetAddress.anyIPv4, _syncPort);
      debugPrint('[Sync] HTTP同步服务器已启动，端口: $_syncPort');

      _syncServer!.listen((request) async {
        debugPrint('[Sync] 收到请求: ${request.method} ${request.uri.path}');
        if (request.method == 'POST' && request.uri.path == '/sync') {
          await _handleSyncRequest(request);
        } else if (request.method == 'GET' && request.uri.path == '/configs') {
          await _handleGetConfigs(request);
        } else if (request.method == 'GET' && request.uri.path == '/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'ok', 'device': (await getLocalDeviceInfo()).toJson()}))
            ..close();
        } else {
          request.response..statusCode = HttpStatus.notFound..close();
        }
      });
    } catch (e) {
      debugPrint('[Sync] HTTP服务器启动失败: $e');
    }
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final configs = parseSyncPayload(data);

      final dbService = DatabaseService();
      await dbService.initialize();
      for (final config in configs) {
        await dbService.insertApiConfig(config);
      }
      debugPrint('[Sync] 已接收 ${configs.length} 个配置');

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'ok', 'received': configs.length}))
        ..close();
    } catch (e) {
      debugPrint('[Sync] 处理同步请求失败: $e');
      request.response..statusCode = HttpStatus.badRequest
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  Future<void> _handleGetConfigs(HttpRequest request) async {
    try {
      final dbService = DatabaseService();
      await dbService.initialize();
      final configs = await dbService.getAllApiConfigs();

      final payload = createSyncPayload(configs);
      debugPrint('[Sync] 发送 ${configs.length} 个配置');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload))
        ..close();
    } catch (e) {
      debugPrint('[Sync] 获取配置失败: $e');
      request.response..statusCode = HttpStatus.internalServerError..close();
    }
  }

  /// 直接通过IP ping检测设备
  Future<DeviceInfo?> pingDevice(String ip) async {
    try {
      if ((await _getLocalIPv4Addresses()).contains(ip)) return null;
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('http://$ip:$_syncPort/ping'));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data.containsKey('device')) {
          final device = DeviceInfo.fromJson(data['device'] as Map<String, dynamic>);
          await upsertDiscoveredDevice(device, sourceIp: ip);
          return device;
        }
      }
    } catch (e) {
      debugPrint('[Sync] Ping $ip 失败: $e');
    }
    return null;
  }

  Future<bool> sendConfigs(DeviceInfo device, List<ApiConfig> configs) async {
    try {
      final payload = createSyncPayload(configs);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.parse('http://${device.ipAddress}:$_syncPort/sync'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close();
      debugPrint('[Sync] 发送结果: ${response.statusCode} $body');
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint('[Sync] 发送配置失败: $e');
      return false;
    }
  }

  Future<List<ApiConfig>> receiveConfigs(DeviceInfo device) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse('http://${device.ipAddress}:$_syncPort/configs'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      client.close();

      final data = jsonDecode(body) as Map<String, dynamic>;
      return parseSyncPayload(data);
    } catch (e) {
      debugPrint('[Sync] 接收配置失败: $e');
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
