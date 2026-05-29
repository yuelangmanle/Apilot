import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/models/api_config.dart';
import '../../../core/models/device_info.dart';

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

  /// 获取本机设备信息
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
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// 启动同步服务（发现 + 同步服务器）
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    await _startDiscovery();
    await _startSyncServer();
  }

  /// 停止同步服务
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

  /// 启动 UDP 发现
  Future<void> _startDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;

      // 监听其他设备的广播
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            _handleDiscoveryMessage(datagram);
          }
        }
      });

      // 定期广播自己的存在
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _broadcastPresence(),
      );

      // 立即广播一次
      _broadcastPresence();
    } catch (e) {
      // UDP discovery not available, continue without it
    }
  }

  void _broadcastPresence() async {
    try {
      final device = await getLocalDeviceInfo();
      final message = jsonEncode({
        'header': _magicHeader,
        'device': device.toJson(),
      });

      _discoverySocket?.send(
        message.codeUnits,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (_) {}
  }

  void _handleDiscoveryMessage(Datagram datagram) {
    try {
      final message = jsonDecode(String.fromCharCodes(datagram.data));
      if (message['header'] != _magicHeader) return;

      final device = DeviceInfo.fromJson(
        message['device'] as Map<String, dynamic>,
      );

      // 不添加自己
      final localIP = _discoverySocket?.address.address;
      if (device.ipAddress == localIP) return;

      // 更新或添加设备
      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        _devices[index] = device;
      } else {
        _devices.add(device);
      }
    } catch (_) {}
  }

  /// 启动 HTTP 同步服务器
  Future<void> _startSyncServer() async {
    try {
      _syncServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _syncPort,
      );

      _syncServer!.listen((request) async {
        if (request.method == 'POST' && request.uri.path == '/sync') {
          await _handleSyncRequest(request);
        } else if (request.method == 'GET' && request.uri.path == '/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('pong')
            ..close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
    } catch (e) {
      // Server start failed, continue without sync server
    }
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      // 处理同步请求
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'received': true,
        }))
        ..close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
    }
  }

  /// 发送配置到指定设备
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

  /// 从指定设备接收配置
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

  /// 创建同步数据包
  static Map<String, dynamic> createSyncPayload(List<ApiConfig> configs) {
    return {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'configs': configs.map((c) => c.toJson()).toList(),
    };
  }

  /// 解析同步数据包
  static List<ApiConfig> parseSyncPayload(Map<String, dynamic> data) {
    final configs = data['configs'] as List;
    return configs
        .map((c) => ApiConfig.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
