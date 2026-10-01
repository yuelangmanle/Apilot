import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/api_protocol_adapter.dart';

/// 本地网关：起一个 OpenAI 兼容反代。
/// 默认仅监听 127.0.0.1（本机回环）；开启局域网模式后监听所有网卡，
/// 局域网设备需携带 X-Gateway-Token 才能使用（防止 Key 暴露）。
class LocalGatewayService {
  LocalGatewayService._();

  static const int defaultPort = 8787;

  static HttpServer? _server;
  static ApiConfig? _target;
  static int _port = defaultPort;
  static String? _token;
  static bool _lanEnabled = false;

  static bool get isRunning => _server != null;
  static int get port => _port;
  static ApiConfig? get target => _target;
  static String? get token => _token;
  static bool get lanEnabled => _lanEnabled;

  /// 启动网关并指向一个配置。
  ///
  /// [lanEnabled] 为 true 时监听所有网卡（供同一局域网内其他设备使用，
  /// 必须携带 [token]）；默认仅监听 127.0.0.1（本机回环）。
  static Future<void> start(ApiConfig config,
      {int? port, bool lanEnabled = false, String? token}) async {
    await stop();
    _target = config;
    _port = port ?? defaultPort;
    _lanEnabled = lanEnabled;
    _token = (lanEnabled && token != null && token.isNotEmpty) ? token : null;
    try {
      _server = await HttpServer.bind(
        lanEnabled ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        _port,
      );
      _server!.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object e) => debugPrint('[Gateway] 通道错误: $e'),
      );
    } catch (e) {
      _server = null;
      rethrow;
    }
  }

  static Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static Future<void> _handle(HttpRequest request) async {
    final target = _target;
    if (target == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    // 局域网模式：非回环来源必须携带 X-Gateway-Token（防 Key 暴露）。
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    final fromLoopback = remote == '127.0.0.1' || remote == '::1';
    if (!fromLoopback && _token != null) {
      final provided = request.headers.value('X-Gateway-Token');
      if (provided != _token) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(jsonEncode({'error': '缺少或错误的网关 Token'}));
        await request.response.close();
        return;
      }
    }
    try {
      final upstreamUri = _upstreamUri(target, request.uri);
      final bodyBytes = await request.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final client = HttpClient();
      try {
        final upstream = await client
            .openUrl(request.method, upstreamUri)
            .timeout(const Duration(seconds: 30));
        upstream.headers.set('Content-Type',
            request.headers.value('Content-Type') ?? 'application/json');
        _applyAuth(upstream, target);
        if (bodyBytes.isNotEmpty) upstream.add(bodyBytes);

        final upstreamResponse =
            await upstream.close().timeout(const Duration(seconds: 120));
        request.response.statusCode = upstreamResponse.statusCode;
        upstreamResponse.headers.forEach((name, values) {
          if (name.toLowerCase() == 'content-length') return;
          for (final value in values) {
            request.response.headers.add(name, value);
          }
        });
        await request.response.addStream(upstreamResponse);
        await request.response.close();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('[Gateway] 转发失败: $e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write(jsonEncode({'error': '网关转发失败: $e'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  /// 拼上游 URL：保留路径与查询，按协议与 base 形态归一。
  static Uri _upstreamUri(ApiConfig config, Uri requestUri) {
    final endpoint =
        requestUri.path.replaceFirst(RegExp(r'^/v1'), '');
    final base = config.baseUrl.trim();
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final needsV1 = !trimmed.endsWith('/v1') &&
        !trimmed.endsWith('/v2') &&
        !trimmed.endsWith('/v3') &&
        !trimmed.endsWith('/api/v3');
    final url =
        '$trimmed${needsV1 ? '/v1' : ''}$endpoint${requestUri.query.isEmpty ? '' : '?${requestUri.query}'}';
    return Uri.parse(url);
  }

  static void _applyAuth(HttpClientRequest request, ApiConfig config) {
    if (ApiProtocolAdapter.isAnthropic(config.protocolId)) {
      request.headers.set('x-api-key', config.apiKey);
      request.headers.set('anthropic-version',
          ApiProtocolAdapter.anthropicVersion);
    } else {
      request.headers.set('Authorization', 'Bearer ${config.apiKey}');
    }
  }
}
