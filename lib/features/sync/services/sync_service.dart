import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/device_info.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/services/api_config_identity.dart';
import '../../../core/services/api_key_cipher.dart';
import '../../../core/services/database_service.dart';

/// 局域网内其他设备通过本机同步端口发起的读取/写入请求，
/// 必须由本机用户在界面上确认后才会执行。
class IncomingSyncRequest {
  final String peerAddress;
  final bool isWrite;
  final int configCount;
  final DateTime receivedAt;
  final void Function(bool allow) _respond;

  const IncomingSyncRequest({
    required this.peerAddress,
    required this.isWrite,
    required this.configCount,
    required this.receivedAt,
    required void Function(bool allow) respond,
  }) : _respond = respond;

  void respond(bool allow) => _respond(allow);
}

class SyncService {
  static const int _discoveryPort = 45678;
  static const int _syncPort = 45679;
  static const String _magicHeader = 'API_MANAGER_SYNC';
  static const String _multicastGroup = '224.0.0.1';
  static const String _deviceIdPrefsKey = 'apilot_sync_device_id';
  static const Duration _requestConfirmTimeout = Duration(seconds: 30);
  static const Duration _clientIoTimeout = Duration(seconds: 15);
  static const Duration _deviceStaleAfter = Duration(seconds: 12);
  static const Duration _localIpCacheTtl = Duration(seconds: 10);
  /// 本机作为同步接收方落库后的回调（供界面刷新列表）。
  static Future<void> Function()? onServerSyncApplied;

  static const String _encryptedHeader = 'X-Apilot-Enc';
  static const String _encryptedHeaderValue = 'fernet-v1';

  /// 通过二维码配对得到的对端加密器，按对端 IP 索引。
  /// 仅覆盖配置读写通道；手动 IP 连接无共享密钥时走明文+确认。
  final Map<String, ApiKeyCipher> _peerCiphers = {};

  final List<DeviceInfo> _devices = [];
  final Set<String> _broadcastSeenDeviceIds = {};
  final String? _localDeviceIdOverride;
  final DatabaseService? _databaseServiceOverride;
  final StreamController<IncomingSyncRequest> _incomingRequests =
      StreamController.broadcast();
  HttpServer? _syncServer;
  RawDatagramSocket? _discoverySocket;
  Timer? _broadcastTimer;
  bool _isRunning = false;
  bool _isDiscoveryRunning = false;
  String? _localDeviceIdCache;
  Set<String>? _localIpCache;
  DateTime? _localIpCacheAt;

  List<DeviceInfo> get discoveredDevices => List.unmodifiable(_devices);

  /// 注册与某个对端 IP 通信时使用的对称密钥（来源：二维码扫描）。
  void registerPeerKey(String ip, String keyBase64) {
    try {
      _peerCiphers[ip] = ApiKeyCipher.fromKeyBase64(keyBase64);
    } catch (e) {
      debugPrint('[Sync] 对端密钥注册失败（将使用明文+确认）: $e');
    }
  }

  void clearPeerKeys() => _peerCiphers.clear();

  Stream<IncomingSyncRequest> get incomingRequests =>
      _incomingRequests.stream;
  bool get isRunning => _isRunning;
  bool get isDiscoveryRunning => _isDiscoveryRunning;

  SyncService({
    String? localDeviceIdOverride,
    DatabaseService? databaseService,
  })  : _localDeviceIdOverride = localDeviceIdOverride,
        _databaseServiceOverride = databaseService;

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
      debugPrint('[Sync] 获取本机IP失败: $e');
    }
    return '127.0.0.1';
  }

  Future<void> start({bool enableDiscovery = true}) async {
    debugPrint('[Sync] 启动同步服务...');
    await _startSyncServer();
    if (enableDiscovery) {
      await startDiscovery();
    }
    _isRunning = _syncServer != null;
    debugPrint('[Sync] 同步服务已启动，IP: ${await _getLocalIP()}');
  }

  Future<void> stop() async {
    _isRunning = false;
    await stopDiscovery(clearDevices: true);
    final server = _syncServer;
    _syncServer = null;
    await server?.close();
    debugPrint('[Sync] 同步服务已停止');
  }

  Future<void> setDiscoveryEnabled(
    bool enabled, {
    bool clearDevices = false,
  }) async {
    if (enabled) {
      await startDiscovery();
    } else {
      await stopDiscovery(clearDevices: clearDevices);
    }
  }

  Future<void> startDiscovery() async {
    if (_isDiscoveryRunning) return;
    await _startDiscovery();
  }

  Future<void> stopDiscovery({bool clearDevices = false}) async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    _isDiscoveryRunning = false;
    if (clearDevices) {
      _devices.clear();
      _broadcastSeenDeviceIds.clear();
    }
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
      _broadcastTimer = Timer.periodic(
          const Duration(seconds: 3), (_) => _broadcastPresence());
      _broadcastPresence(); // 立即广播一次
      _isDiscoveryRunning = true;
      debugPrint('[Sync] UDP发现已启动，端口: $_discoveryPort');
    } catch (e) {
      _isDiscoveryRunning = false;
      debugPrint('[Sync] UDP发现启动失败: $e');
    }
  }

  void _broadcastPresence() async {
    try {
      final device = await getLocalDeviceInfo();
      final message =
          jsonEncode({'header': _magicHeader, 'device': device.toJson()});
      // 必须按 UTF-8 编码：中文主机名等非 ASCII 内容用 codeUnits 会丢字节。
      final data = utf8.encode(message);

      // 同时发送到多播组和广播地址
      try {
        _discoverySocket?.send(
            data, InternetAddress(_multicastGroup), _discoveryPort);
      } catch (_) {}
      try {
        _discoverySocket?.send(
            data, InternetAddress('255.255.255.255'), _discoveryPort);
      } catch (_) {}
    } catch (e) {
      debugPrint('[Sync] 广播失败: $e');
    }
  }

  void _handleDiscoveryMessage(Datagram datagram) async {
    try {
      final message = jsonDecode(utf8.decode(datagram.data));
      if (message['header'] != _magicHeader) return;

      final device =
          DeviceInfo.fromJson(message['device'] as Map<String, dynamic>);
      await upsertDiscoveredDevice(device,
          sourceIp: datagram.address.address, viaBroadcast: true);
    } catch (e) {
      debugPrint('[Sync] 解析发现消息失败: $e');
    }
  }

  Future<bool> upsertDiscoveredDevice(
    DeviceInfo device, {
    String? sourceIp,
    bool viaBroadcast = false,
  }) async {
    if (await _isLocalDevice(device, sourceIp: sourceIp)) return false;

    final normalized = DeviceInfo(
      id: device.id,
      name: device.name.isEmpty ? '未知设备' : device.name,
      platform: device.platform,
      ipAddress: sourceIp != null && _isUsableRemoteIP(sourceIp)
          ? sourceIp
          : device.ipAddress,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
    if (viaBroadcast) _broadcastSeenDeviceIds.add(normalized.id);

    final index = _devices.indexWhere((existing) {
      if (existing.id == normalized.id) return true;
      return existing.ipAddress == normalized.ipAddress &&
          normalized.ipAddress.isNotEmpty;
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

  /// 清理长时间未广播的设备（仅针对通过 UDP 广播发现的条目；
  /// 手动添加的设备不受影响）。返回被移除的设备数。
  int pruneStaleDevices() {
    final cutoff = DateTime.now().subtract(_deviceStaleAfter);
    final removed = _devices
        .where((device) =>
            _broadcastSeenDeviceIds.contains(device.id) &&
            device.lastSeen.isBefore(cutoff))
        .toList();
    if (removed.isEmpty) return 0;
    _devices.removeWhere(removed.contains);
    for (final device in removed) {
      _broadcastSeenDeviceIds.remove(device.id);
    }
    return removed.length;
  }

  Future<bool> _isLocalDevice(DeviceInfo device, {String? sourceIp}) async {
    final localDeviceId = await _getLocalDeviceId();
    if (device.id == localDeviceId) return true;

    final localIPs = await _getLocalIPv4Addresses();
    if (localIPs.contains(device.ipAddress)) return true;
    if (sourceIp != null && localIPs.contains(sourceIp)) return true;

    final socketAddress = _discoverySocket?.address.address;
    if (socketAddress != null && socketAddress != '0.0.0.0') {
      if (device.ipAddress == socketAddress || sourceIp == socketAddress) {
        return true;
      }
    }

    return false;
  }

  bool _isUsableRemoteIP(String ip) {
    return ip.isNotEmpty && ip != '0.0.0.0' && ip != '127.0.0.1';
  }

  Future<Set<String>> _getLocalIPv4Addresses() async {
    final now = DateTime.now();
    final cached = _localIpCache;
    final cachedAt = _localIpCacheAt;
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _localIpCacheTtl) {
      return cached;
    }
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
    _localIpCache = addresses;
    _localIpCacheAt = now;
    return addresses;
  }

  Future<void> _startSyncServer() async {
    if (_syncServer != null) return;
    HttpServer? server;
    // 上一个实例可能仍在关闭端口，短暂重试避免 EADDRINUSE 让同步永久失效。
    for (var attempt = 1; attempt <= 5; attempt++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, _syncPort);
        break;
      } on SocketException catch (e) {
        if (attempt == 5) {
          debugPrint('[Sync] HTTP服务器启动失败: $e');
          return;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    _syncServer = server;
    _isRunning = true;
    debugPrint('[Sync] HTTP同步服务器已启动，端口: $_syncPort');

    server!.listen((request) async {
      debugPrint('[Sync] 收到请求: ${request.method} ${request.uri.path}');
      if (request.method == 'POST' && request.uri.path == '/sync') {
        await _handleSyncRequest(request);
      } else if (request.method == 'GET' && request.uri.path == '/configs') {
        await _handleGetConfigs(request);
      } else if (request.method == 'GET' && request.uri.path == '/ping') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'ok',
            'device': (await getLocalDeviceInfo()).toJson()
          }))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  }

  /// 弹出本机确认。没有 UI 监听或超时未确认时默认拒绝（fail closed）。
  Future<bool> _confirmIncoming({
    required String peerAddress,
    required bool isWrite,
    int configCount = 0,
  }) async {
    final completer = Completer<bool>();
    _incomingRequests.add(IncomingSyncRequest(
      peerAddress: peerAddress,
      isWrite: isWrite,
      configCount: configCount,
      receivedAt: DateTime.now(),
      respond: (allow) {
        if (!completer.isCompleted) completer.complete(allow);
      },
    ));
    try {
      return await completer.future.timeout(_requestConfirmTimeout);
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _handleSyncRequest(HttpRequest request) async {
    try {
      final cipher = _requestCipher(request);
      final body = await utf8.decoder.bind(request).join();
      final data =
          jsonDecode(_maybeDecrypt(cipher, body)) as Map<String, dynamic>;
      final configs = parseSyncPayload(data);

      final allowed = await _confirmIncoming(
        peerAddress: request.connectionInfo?.remoteAddress.address ?? '未知设备',
        isWrite: true,
        configCount: configs.length,
      );
      if (!allowed) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': '本机未确认此次同步请求'}))
          ..close();
        return;
      }

      final inserted = await storeSyncedConfigs(configs);
      debugPrint('[Sync] 已接收 ${configs.length} 个配置，新增 $inserted 个');
      // 通知界面层刷新（服务器端接收不经过 provider 的常规路径）。
      onServerSyncApplied?.call();

      _writeJsonResponse(request, cipher,
          {'status': 'ok', 'received': configs.length, 'inserted': inserted},
          statusCode: HttpStatus.ok);
    } catch (e) {
      debugPrint('[Sync] 处理同步请求失败: $e');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  /// 请求带加密头时返回对应的对端加密器，否则 null。
  ApiKeyCipher? _requestCipher(HttpRequest request) {
    if (request.headers.value(_encryptedHeader) != _encryptedHeaderValue) {
      return null;
    }
    final remote = request.connectionInfo?.remoteAddress.address;
    if (remote == null) return null;
    final cipher = _peerCiphers[remote];
    if (cipher == null) {
      debugPrint('[Sync] 收到加密请求但没有对应的配对密钥: $remote');
    }
    return cipher;
  }

  String _maybeDecrypt(ApiKeyCipher? cipher, String body) {
    if (cipher == null) return body;
    try {
      final wrapper = jsonDecode(body) as Map<String, dynamic>;
      return cipher.decrypt(wrapper['enc'] as String? ?? '');
    } catch (e) {
      throw FormatException('同步请求解密失败: $e');
    }
  }

  String? _maybeEncrypt(ApiKeyCipher? cipher, String payload) {
    if (cipher == null) return null;
    return jsonEncode({'enc': cipher.encrypt(payload)});
  }

  void _writeJsonResponse(
    HttpRequest request,
    ApiKeyCipher? cipher,
    Map<String, dynamic> payload, {
    int statusCode = HttpStatus.ok,
  }) {
    final plain = jsonEncode(payload);
    final body = _maybeEncrypt(cipher, plain) ?? plain;
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }

  Future<void> _handleGetConfigs(HttpRequest request) async {
    try {
      final allowed = await _confirmIncoming(
        peerAddress: request.connectionInfo?.remoteAddress.address ?? '未知设备',
        isWrite: false,
      );
      if (!allowed) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': '本机未确认此次读取请求'}))
          ..close();
        return;
      }

      final dbService = _databaseServiceOverride ?? DatabaseService();
      await dbService.initialize();
      final configs = await dbService.getAllApiConfigs();

      final payload = createSyncPayload(configs);
      debugPrint('[Sync] 发送 ${configs.length} 个配置');
      _writeJsonResponse(request, _requestCipher(request), payload);
    } catch (e) {
      debugPrint('[Sync] 获取配置失败: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    }
  }

  /// 直接通过IP ping检测设备
  Future<DeviceInfo?> pingDevice(String ip) async {
    HttpClient? client;
    try {
      if ((await _getLocalIPv4Addresses()).contains(ip)) return null;
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client
          .getUrl(Uri.parse('http://$ip:$_syncPort/ping'))
          .timeout(_clientIoTimeout);
      final response = await request.close().timeout(_clientIoTimeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(_clientIoTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (data.containsKey('device')) {
          final device =
              DeviceInfo.fromJson(data['device'] as Map<String, dynamic>);
          await upsertDiscoveredDevice(device, sourceIp: ip);
          return device;
        }
      }
    } catch (e) {
      debugPrint('[Sync] Ping $ip 失败: $e');
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  Future<bool> sendConfigs(DeviceInfo device, List<ApiConfig> configs) async {
    HttpClient? client;
    try {
      final cipher = _peerCiphers[device.ipAddress];
      final payload = createSyncPayload(configs);
      final bodyText = _maybeEncrypt(cipher, jsonEncode(payload)) ??
          jsonEncode(payload);
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .postUrl(Uri.parse('http://${device.ipAddress}:$_syncPort/sync'))
          .timeout(_clientIoTimeout);
      request.headers.contentType = ContentType.json;
      if (cipher != null) {
        request.headers.add(_encryptedHeader, _encryptedHeaderValue);
      }
      request.write(bodyText);

      final response = await request.close().timeout(_clientIoTimeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(_clientIoTimeout);
      debugPrint('[Sync] 发送结果: ${response.statusCode} $body');
      if (response.statusCode == HttpStatus.forbidden) {
        debugPrint('[Sync] 对方未确认同步请求');
      }
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint('[Sync] 发送配置失败: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<List<ApiConfig>> receiveConfigs(DeviceInfo device) async {
    HttpClient? client;
    try {
      final cipher = _peerCiphers[device.ipAddress];
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client
          .getUrl(Uri.parse('http://${device.ipAddress}:$_syncPort/configs'))
          .timeout(_clientIoTimeout);
      if (cipher != null) {
        request.headers.add(_encryptedHeader, _encryptedHeaderValue);
      }
      final response = await request.close().timeout(_clientIoTimeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(_clientIoTimeout);

      if (response.statusCode != HttpStatus.ok) {
        debugPrint('[Sync] 接收配置失败: 对方返回 ${response.statusCode}');
        return [];
      }
      final data = jsonDecode(_maybeDecrypt(cipher, body)) as Map<String, dynamic>;
      return parseSyncPayload(data);
    } catch (e) {
      debugPrint('[Sync] 接收配置失败: $e');
      return [];
    } finally {
      client?.close(force: true);
    }
  }

  /// 接收其他设备推送/拉取的配置并合并入库。
  ///
  /// 合并策略：同一 id 或业务等价（地址+Key+默认模型相同）的配置按
  /// `updatedAt` 新者胜，旧的本地编辑不会被旧数据回滚；其余按新配置插入。
  Future<int> storeSyncedConfigs(List<ApiConfig> configs) async {
    final databaseService = _databaseServiceOverride ?? DatabaseService();
    await databaseService.initialize();
    final db = await databaseService.database;
    // 全程单事务：并发推送各自的 read-modify-write 不再互相踩快照。
    return db.transaction((txn) async {
      // 索引包含回收站内容：同步进来的同款不应复活本机已删除的配置，
      // 而是把较新数据写回回收站内的对应条目（保持隐藏）。
      final existing = await databaseService.getAllApiConfigs(
        includeDeleted: true,
        executor: txn,
      );
      final byId = {for (final config in existing) config.id: config};

      var inserted = 0;
      for (final config in configs) {
        final sameId = byId[config.id];
        if (sameId != null) {
          if (!config.updatedAt.isAfter(sameId.updatedAt)) continue;
          final merged =
              config.copyWith(id: sameId.id, createdAt: sameId.createdAt);
          final row = _configRow(merged, databaseService);
          // 回收站保护：同 id 合并不改变本机的删除标记。
          row['deleted_at'] = sameId.deletedAt?.toIso8601String();
          await txn.update(
            'api_configs',
            row,
            where: 'id = ?',
            whereArgs: [merged.id],
          );
          byId[sameId.id] = merged;
          continue;
        }

        ApiConfig? equivalent;
        for (final candidate in byId.values) {
          if (ApiConfigIdentity.matches(candidate, config)) {
            equivalent = candidate;
            break;
          }
        }
        if (equivalent != null) {
          if (config.updatedAt.isAfter(equivalent.updatedAt)) {
            final merged = config.copyWith(
              id: equivalent.id,
              createdAt: equivalent.createdAt,
            );
            final row = _configRow(merged, databaseService);
            row['deleted_at'] = equivalent.deletedAt?.toIso8601String();
            await txn.update(
              'api_configs',
              row,
              where: 'id = ?',
              whereArgs: [merged.id],
            );
            byId[equivalent.id] = merged;
          }
          continue;
        }

        await txn.insert(
          'api_configs',
          _configRow(config, databaseService),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        byId[config.id] = config;
        inserted++;
      }
      return inserted;
    });
  }

  /// 在事务内生成一行配置（复用 DatabaseService 的加密与列映射）。
  Map<String, Object?> _configRow(
    ApiConfig config,
    DatabaseService databaseService,
  ) {
    return databaseService.buildConfigRow(config);
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
    return configs
        .map((c) => ApiConfig.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
