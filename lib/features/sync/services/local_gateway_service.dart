import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/api_protocol_adapter.dart';
import '../../../core/services/local_llm/local_llm_engine.dart';

/// 网关的本机模型后端：直接用已下载的 GGUF 推理，
/// 对外暴露 OpenAI 兼容的 /v1/chat/completions（离线、不消耗额度）。
class GatewayLocalModel {
  final String filePath;
  final String name;

  const GatewayLocalModel({required this.filePath, required this.name});

  /// 对外提供的模型 id（客户端填的 model 名）。
  String get id => name.replaceAll(RegExp(r'\.gguf$'), '');
}

/// 本地网关：起一个 OpenAI 兼容反代。
/// 默认仅监听 127.0.0.1（本机回环）；开启局域网模式后监听所有网卡，
/// 局域网设备需携带 X-Gateway-Token 才能使用（防止 Key 暴露）。
///
/// 目标可以是云端 API 配置（转发，Key 由网关注入），
/// 也可以是本机已下载的 GGUF 模型（本地推理，完全离线）。
class LocalGatewayService {
  LocalGatewayService._();

  static const int defaultPort = 8787;

  static HttpServer? _server;
  static ApiConfig? _target;
  static GatewayLocalModel? _localTarget;
  static int _port = defaultPort;
  static String? _token;
  static bool _lanEnabled = false;
  static LocalLlmEngine? _localEngine;
  /// 本地推理串行化：单引擎不能并发生成。
  static Future<void> _localQueue = Future<void>.value();

  static bool get isRunning => _server != null;
  static int get port => _port;
  static ApiConfig? get target => _target;
  static GatewayLocalModel? get localTarget => _localTarget;
  static String? get token => _token;
  static bool get lanEnabled => _lanEnabled;

  /// 启动网关。二选一：云端 [config]（转发）或 [localModel]（本地推理）。
  ///
  /// [lanEnabled] 为 true 时监听所有网卡（供同一局域网内其他设备使用，
  /// 必须携带 [token]）；默认仅监听 127.0.0.1（本机回环）。
  static Future<void> start(
    ApiConfig? config, {
    GatewayLocalModel? localModel,
    int? port,
    bool lanEnabled = false,
    String? token,
  }) async {
    if (config == null && localModel == null) {
      throw ArgumentError('必须指定云端配置或本地模型');
    }
    await stop();
    _target = config;
    _localTarget = localModel;
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
    final engine = _localEngine;
    _localEngine = null;
    _localTarget = null;
    await engine?.dispose();
  }

  static Future<void> _handle(HttpRequest request) async {
    final localModel = _localTarget;
    final target = _target;
    if (localModel == null && target == null) {
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
    // 本地模型后端：/v1/models 与 /v1/chat/completions 本地处理。
    if (localModel != null) {
      final path = request.uri.path.replaceFirst(RegExp(r'^/v1'), '');
      if (path == '/models') {
        await _respondModels(request, localModel);
        return;
      }
      if (path == '/chat/completions') {
        await _handleLocalChat(request, localModel);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': '本地模型网关仅支持 /v1/chat/completions 与 /v1/models',
      }));
      await request.response.close();
      return;
    }
    try {
      final upstreamUri = _upstreamUri(target!, request.uri);
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

  /// 本地模型：/v1/models 返回当前加载的模型。
  static Future<void> _respondModels(
      HttpRequest request, GatewayLocalModel model) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'object': 'list',
      'data': [
        {
          'id': model.id,
          'object': 'model',
          'owned_by': 'apilot-local',
        },
      ],
    }));
    await request.response.close();
  }

  /// 本地模型：OpenAI 兼容的 chat completions（支持 stream）。
  static Future<void> _handleLocalChat(
      HttpRequest request, GatewayLocalModel model) async {
    Map<String, dynamic> body;
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('body 不是 JSON 对象');
      body = Map<String, dynamic>.from(decoded);
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'error': {'message': '请求体不是合法 JSON: $e'}}));
      await request.response.close();
      return;
    }

    // 消息解析：本地模型只接受文本；图片要明确报错而不是静默丢弃。
    final messages = <LlamaChatMessage>[];
    var hasImage = false;
    for (final entry in (body['messages'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final roleText = entry['role']?.toString() ?? 'user';
      final content = entry['content'];
      final buffer = StringBuffer();
      if (content is String) {
        buffer.write(content);
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type']?.toString();
          if (type == 'text') {
            buffer.write(part['text']?.toString() ?? '');
          } else if (type == 'image_url' || type == 'input_image') {
            hasImage = true;
          }
        }
      }
      final role = switch (roleText) {
        'system' => LlamaChatRole.system,
        'assistant' => LlamaChatRole.assistant,
        _ => LlamaChatRole.user,
      };
      messages.add(LlamaChatMessage.fromText(role: role, text: buffer.toString()));
    }
    if (hasImage) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {
          'message': '当前本地模型网关只支持文本输入：请改用支持多模态的模型，'
              '或去掉消息中的图片。',
        },
      }));
      await request.response.close();
      return;
    }
    if (messages.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'error': {'message': 'messages 不能为空'}}));
      await request.response.close();
      return;
    }

    final stream = body['stream'] == true;
    final maxTokens = (body['max_tokens'] as num?)?.toInt() ?? 512;
    final temp = (body['temperature'] as num?)?.toDouble() ?? 0.8;

    // 串行执行：单引擎不能并发生成。
    final completer = Completer<void>();
    final previous = _localQueue;
    _localQueue = completer.future;
    await previous;
    try {
      final engine = await _ensureEngine(model);
      if (engine == null) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'message': '本地模型加载失败：文件可能已被删除'},
        }));
        await request.response.close();
        return;
      }

      final id = 'chatcmpl-local-${DateTime.now().millisecondsSinceEpoch}';
      final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (stream) {
        request.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        final thinkingFallback = StringBuffer();
        var sawContent = false;
        await for (final chunk in engine.generateStream(messages,
            maxTokens: maxTokens, temp: temp, suppressThinking: true)) {
          if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
            thinkingFallback.write(chunk.thinking);
          }
          final delta = chunk.content;
          if (delta == null || delta.isEmpty) continue;
          sawContent = true;
          request.response.write('data: ${jsonEncode({
                'id': id,
                'object': 'chat.completion.chunk',
                'created': created,
                'model': model.id,
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': delta},
                    'finish_reason': null,
                  }
                ],
              })}\n\n');
          await request.response.flush();
        }
        // 全是思考、没有正文时，把思考内容当结果返回（否则客户端拿到空回复）。
        if (!sawContent && thinkingFallback.isNotEmpty) {
          request.response.write('data: ${jsonEncode({
                'id': id,
                'object': 'chat.completion.chunk',
                'created': created,
                'model': model.id,
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': thinkingFallback.toString()},
                    'finish_reason': null,
                  }
                ],
              })}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
      } else {
        final buffer = StringBuffer();
        final thinking = StringBuffer();
        await for (final chunk in engine.generateStream(messages,
            maxTokens: maxTokens, temp: temp, suppressThinking: true)) {
          if (chunk.content != null) buffer.write(chunk.content);
          if (chunk.thinking != null) thinking.write(chunk.thinking);
        }
        if (buffer.isEmpty && thinking.isNotEmpty) {
          buffer.write(thinking.toString());
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'id': id,
          'object': 'chat.completion',
          'created': created,
          'model': model.id,
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': buffer.toString(),
              },
              'finish_reason': 'stop',
            }
          ],
        }));
      }
      await request.response.close();
    } catch (e) {
      debugPrint('[Gateway] 本地推理失败: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': {'message': '本地推理失败: $e'}}));
        await request.response.close();
      } catch (_) {}
    } finally {
      completer.complete();
    }
  }

  /// 确保引擎指向目标模型（同一实例复用；切换模型时重新加载）。
  static Future<LocalLlmEngine?> _ensureEngine(GatewayLocalModel model) async {
    var engine = _localEngine;
    if (engine != null && engine.isLoaded && engine.loadedModelPath == model.filePath) {
      return engine;
    }
    if (!File(model.filePath).existsSync()) return null;
    engine ??= LocalLlmEngine();
    try {
      await engine.loadModel(model.filePath);
    } catch (e) {
      debugPrint('[Gateway] 本地模型加载失败: $e');
      return null;
    }
    _localEngine = engine;
    return engine;
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
