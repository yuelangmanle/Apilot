import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/api_protocol_adapter.dart';

/// 本地网关：在 127.0.0.1 起一个 OpenAI 兼容反代。
/// 任意 SDK/工具把 base_url 指向 http://127.0.0.1:<port>/v1 即可
/// 使用 Apilot 所选配置的 Key 与端点，请求/响应只在本机回环流动。
class LocalGatewayService {
  LocalGatewayService._();

  static const int defaultPort = 8787;

  static HttpServer? _server;
  static ApiConfig? _target;
  static int _port = defaultPort;

  static bool get isRunning => _server != null;
  static int get port => _port;
  static ApiConfig? get target => _target;

  /// 启动网关并指向一个配置。
  static Future<void> start(ApiConfig config, {int? port}) async {
    await stop();
    _target = config;
    _port = port ?? defaultPort;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
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
