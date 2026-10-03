import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:llamadart/llamadart.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/api_protocol_adapter.dart';
import '../../../core/services/ai/ai_service.dart';
import '../../../core/services/ai/tool_registry.dart';
import '../../../core/services/local_llm/download_task_store.dart';
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
  static const int _maxGatewayImageBytes = 8 * 1024 * 1024;

  static HttpServer? _server;
  static ApiConfig? _target;
  static GatewayLocalModel? _localTarget;
  static int _port = defaultPort;
  static String? _token;
  static bool _lanEnabled = false;
  static LocalLlmEngine? _localEngine;
  static bool _ownsLocalEngine = false;
  static bool _localRequestsEnabled = false;

  /// 本地推理串行化：单引擎不能并发生成。
  static Future<void> _localQueue = Future<void>.value();
  static DateTime? _lastRequestAt;
  static String? _lastRequestPath;

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
    if (lanEnabled && (token == null || token.trim().isEmpty)) {
      throw ArgumentError('局域网模式必须设置非空网关 Token');
    }
    await stop();
    _target = config;
    _localTarget = localModel;
    _port = port ?? defaultPort;
    _lanEnabled = lanEnabled;
    _token = lanEnabled ? token!.trim() : null;
    try {
      _server = await HttpServer.bind(
        lanEnabled ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        _port,
      );
      _port = _server!.port;
      _server!.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object e) => debugPrint('[Gateway] 通道错误: $e'),
      );
      // 安卓：拉起前台服务（常驻通知 + 唤醒锁），否则切后台就被冻结。
      await _setForegroundService(running: true, port: _port);
      _localRequestsEnabled = localModel != null;
    } catch (e) {
      _server = null;
      _localRequestsEnabled = false;
      rethrow;
    }
  }

  static Future<void> stop() async {
    _localRequestsEnabled = false;
    final server = _server;
    _server = null;
    await server?.close(force: true);
    await _setForegroundService(running: false, port: _port);
    await setOverlayVisible(false);
    final engine = _localEngine;
    // 自有引擎可以主动中止生成；共享聊天引擎不能在这里强制取消，
    // 否则关闭网关会误杀聊天页当前回复。两者都先等待队列结束，
    // 再决定是否释放 native 句柄，避免 Vulkan/生成中的 use-after-dispose。
    if (_ownsLocalEngine) engine?.cancelGeneration();
    try {
      await _localQueue;
    } catch (_) {}
    _localQueue = Future<void>.value();
    _localEngine = null;
    final ownsEngine = _ownsLocalEngine;
    _ownsLocalEngine = false;
    _target = null;
    _localTarget = null;
    if (ownsEngine) await engine?.dispose();
  }

  static const MethodChannel _foregroundChannel =
      MethodChannel('com.apilot/gateway_foreground');
  static const MethodChannel _overlayChannel =
      MethodChannel('com.apilot/gateway_overlay');

  /// 网关是否已在别处成功处理过请求（悬浮窗展示用）。
  static int handledRequests = 0;

  /// 悬浮窗：是否可用（安卓且已授予"显示在其他应用上层"权限）。
  static Future<bool> canShowOverlay() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _overlayChannel.invokeMethod<bool>('canShow') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 请求悬浮窗权限（跳到系统设置页）。
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _overlayChannel.invokeMethod<void>('requestPermission');
    } catch (e) {
      debugPrint('[Gateway] 申请悬浮窗权限失败: $e');
    }
  }

  /// 显示/隐藏悬浮窗。
  static Future<bool> setOverlayVisible(bool visible) async {
    if (!Platform.isAndroid) return false;
    try {
      if (visible) {
        final ok = await _overlayChannel.invokeMethod<bool>(
                'show', {'port': _port, 'requests': handledRequests}) ??
            false;
        return ok;
      }
      await _overlayChannel.invokeMethod<void>('hide');
      return true;
    } catch (e) {
      debugPrint('[Gateway] 悬浮窗操作失败: $e');
      return false;
    }
  }

  /// 刷新悬浮窗上的请求计数。
  static Future<void> refreshOverlay() async {
    if (!Platform.isAndroid) return;
    try {
      await _overlayChannel.invokeMethod<void>(
          'update', {'port': _port, 'requests': handledRequests});
    } catch (_) {}
  }

  /// 开关安卓前台服务（桌面/其他平台是空操作）。
  static Future<void> _setForegroundService({
    required bool running,
    required int port,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (running) {
        // Android 13+ 需要 POST_NOTIFICATIONS，否则前台服务跑了但状态栏看不到。
        await _ensureNotificationPermission();
      }
      await _foregroundChannel.invokeMethod<void>(
        running ? 'start' : 'stop',
        running ? {'port': port} : null,
      );
      debugPrint('[Gateway] 前台服务 ${running ? '已启动' : '已停止'}');
    } catch (e) {
      debugPrint('[Gateway] 前台服务调用失败: $e');
    }
  }

  /// 申请通知权限（用户拒绝时不阻断网关，只是看不到常驻通知）。
  static Future<void> _ensureNotificationPermission() async {
    try {
      if (!Platform.isAndroid) return;
      var status = await Permission.notification.status;
      if (!status.isGranted) {
        status = await Permission.notification.request();
      }
      debugPrint('[Gateway] 通知权限: ${status.isGranted ? '已授予' : '未授予'
          '（前台服务仍运行，但状态栏看不到提示）'}');
    } catch (e) {
      debugPrint('[Gateway] 申请通知权限失败: $e');
    }
  }

  static Future<void> _handle(HttpRequest request) async {
    handledRequests++;
    _lastRequestAt = DateTime.now();
    _lastRequestPath = request.uri.path;
    unawaited(refreshOverlay());
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
    if (!fromLoopback && _lanEnabled) {
      final provided = request.headers.value('X-Gateway-Token');
      if (_token == null || provided != _token) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(jsonEncode({'error': '缺少或错误的网关 Token'}));
        await request.response.close();
        return;
      }
    }
    final path = request.uri.path.replaceFirst(RegExp(r'^/v1'), '');
    if (path == '/health' || path == '/diagnostics') {
      await _respondDiagnostics(request, detailed: path == '/diagnostics');
      return;
    }
    // 本地模型后端：/v1/models 与 /v1/chat/completions 本地处理。
    if (localModel != null) {
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

  /// 只读诊断接口，供调试脚本、模拟器和第三方客户端检查每一步状态。
  /// 不执行任意工具，也不返回 API Key 或完整本地路径；局域网模式仍受
  /// 网关 Token 保护。`/health` 返回精简状态，`/diagnostics` 返回细节。
  static Future<void> _respondDiagnostics(
    HttpRequest request, {
    required bool detailed,
  }) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': '诊断接口只支持 GET'}));
      await request.response.close();
      return;
    }
    final local = _localTarget;
    final localFile = local == null ? null : File(local.filePath);
    final file = localFile;
    final engine = _localEngine;
    final tasks = await DownloadTaskStore.list();
    final modelReady = local == null ||
        (file != null && file.existsSync() && file.lengthSync() > 0);
    final body = <String, dynamic>{
      'ok': isRunning && modelReady,
      'object': detailed ? 'apilot.diagnostics' : 'apilot.health',
      'service': {
        'running': isRunning,
        'port': _port,
        'lanEnabled': _lanEnabled,
        'mode': local == null ? 'cloud_proxy' : 'local_model',
        'handledRequests': handledRequests,
        'lastRequestAt': _lastRequestAt?.toIso8601String(),
        'lastRequestPath': _lastRequestPath,
      },
      'model': {
        'id': local?.id,
        'name': local?.name,
        'fileName': file?.uri.pathSegments.last,
        'fileExists': file?.existsSync() ?? false,
        'fileSizeBytes': file?.existsSync() == true ? file!.lengthSync() : 0,
        'ready': modelReady,
      },
      'engine': {
        'loaded': engine?.isLoaded ?? false,
        'loading': engine?.isLoading ?? false,
        'generating': engine?.isGenerating ?? false,
        'loadedModel': _baseName(engine?.loadedModelPath),
        'visionEnabled': engine?.supportsVision ?? false,
        'projector': _baseName(engine?.projectorPath),
        'projectorCandidate': engine?.hasVisionCandidate ?? false,
        'projectorError': engine?.projectorError,
      },
      if (detailed)
        'tools': {
          'masterEnabled': ToolRegistry.masterEnabled,
          'enabled':
              ToolRegistry.enabledTools.map((tool) => tool.name).toList(),
        },
      if (detailed)
        'downloads': {
          'active': tasks.where((task) => task.status == 'downloading').length,
          'failed': tasks.where((task) => task.status == 'failed').length,
          'completed': tasks.where((task) => task.status == 'completed').length,
          'recent': [
            for (final task in tasks.take(10))
              {
                'id': task.id,
                'fileName': task.fileName,
                'status': task.status,
                'receivedBytes': task.receivedBytes,
                'totalBytes': task.totalBytes,
                'error': task.error,
              },
          ],
        },
    };
    request.response.headers.contentType = ContentType.json;
    if (request.method != 'HEAD') request.response.write(jsonEncode(body));
    await request.response.close();
  }

  static String? _baseName(String? path) {
    if (path == null || path.isEmpty) return null;
    return File(path).uri.pathSegments.last;
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
      request.response.write(jsonEncode({
        'error': {'message': '请求体不是合法 JSON: $e'}
      }));
      await request.response.close();
      return;
    }

    final rawMessages = body['messages'];
    if (rawMessages is! List) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {'message': 'messages 必须是数组'},
      }));
      await request.response.close();
      return;
    }

    // 消息解析：兼容 OpenAI 的文本 + data URL 图片格式。
    final messages = <LlamaChatMessage>[];
    var hasImage = false;
    String? imageError;
    for (final entry in rawMessages) {
      if (entry is! Map) continue;
      final roleText = entry['role']?.toString() ?? 'user';
      final content = entry['content'];
      final buffer = StringBuffer();
      final parts = <LlamaContentPart>[];
      var messageHasImage = false;
      if (content is String) {
        buffer.write(content);
        if (content.isNotEmpty) parts.add(LlamaTextContent(content));
      } else if (content is List) {
        for (final part in content) {
          if (part is! Map) continue;
          final type = part['type']?.toString();
          if (type == 'text') {
            final text = part['text']?.toString() ?? '';
            buffer.write(text);
            if (text.isNotEmpty) parts.add(LlamaTextContent(text));
          } else if (type == 'image_url' || type == 'input_image') {
            try {
              parts.add(_parseGatewayImage(part));
              hasImage = true;
              messageHasImage = true;
            } catch (e) {
              imageError = e.toString();
              break;
            }
          }
        }
      }
      if (imageError != null) break;
      final role = switch (roleText) {
        'system' => LlamaChatRole.system,
        'assistant' => LlamaChatRole.assistant,
        _ => LlamaChatRole.user,
      };
      if (parts.isNotEmpty && messageHasImage) {
        messages.add(LlamaChatMessage.withContent(role: role, content: parts));
      } else {
        messages.add(
            LlamaChatMessage.fromText(role: role, text: buffer.toString()));
      }
    }
    if (imageError != null) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {
          'message':
              '图片格式不受支持：$imageError；请使用不超过 8MB 的 data:image/*;base64 图片。',
        },
      }));
      await request.response.close();
      return;
    }
    if (messages.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': {'message': 'messages 不能为空'}
      }));
      await request.response.close();
      return;
    }

    final stream = body['stream'] == true;
    final maxTokens = body['max_tokens'] is num
        ? (body['max_tokens'] as num).toInt().clamp(1, 32768).toInt()
        : 512;
    final temp = body['temperature'] is num
        ? (body['temperature'] as num).toDouble().clamp(0.0, 2.0).toDouble()
        : 0.8;

    // 串行执行：单引擎不能并发生成。
    final completer = Completer<void>();
    final previous = _localQueue;
    _localQueue = completer.future;
    await previous;
    if (!_localRequestsEnabled || !identical(_localTarget, model)) {
      try {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {'message': '本地网关正在停止，请稍后重试'},
        }));
        await request.response.close();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
      return;
    }
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
      if (hasImage && !engine.supportsVision && !await engine.ensureVision()) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': {
            'message':
                '当前本地模型没有可用的视觉投影：${engine.projectorError ?? '请先下载并配对对应 mmproj 文件'}',
          },
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
        request.response.write(jsonEncode({
          'error': {'message': '本地推理失败: $e'}
        }));
        await request.response.close();
      } catch (_) {}
    } finally {
      completer.complete();
    }
  }

  static LlamaImageContent _parseGatewayImage(Map part) {
    Object? value = part['image_url'] ?? part['input_image'] ?? part['image'];
    if (value is Map) {
      value = value['url'] ?? value['data'] ?? value['image_url'];
    }
    final source = value?.toString().trim() ?? '';
    if (!source.startsWith('data:')) {
      throw const FormatException('仅支持 data URL 图片，不能读取远程 URL 或任意本地路径');
    }
    final comma = source.indexOf(',');
    if (comma <= 5 ||
        !source.substring(0, comma).toLowerCase().contains(';base64')) {
      throw const FormatException('data URL 必须包含 base64 编码');
    }
    final encoded = source.substring(comma + 1).replaceAll(RegExp(r'\s+'), '');
    final bytes = base64Decode(encoded);
    if (bytes.length > _maxGatewayImageBytes) {
      throw const FormatException('图片超过 8MB 限制');
    }
    return LlamaImageContent(bytes: bytes);
  }

  /// 确保引擎指向目标模型（同一实例复用；切换模型时重新加载）。
  static Future<LocalLlmEngine?> _ensureEngine(GatewayLocalModel model) async {
    var engine = _localEngine;
    if (engine == null) {
      final shared = AiService.registeredLocalEngine;
      final sharedMatches = shared != null &&
          !shared.isDisposed &&
          (shared.loadedModelPath == model.filePath ||
              shared.loadingKey?.startsWith('${model.filePath}#') == true);
      if (sharedMatches) {
        engine = shared;
        _ownsLocalEngine = false;
      }
    }
    if (engine != null &&
        engine.isLoaded &&
        engine.loadedModelPath == model.filePath) {
      return engine;
    }
    if (!File(model.filePath).existsSync()) return null;
    final sharedLoadingTarget = engine != null &&
        !_ownsLocalEngine &&
        engine.loadingKey?.startsWith('${model.filePath}#') == true;
    if (engine == null ||
        (!_ownsLocalEngine &&
            engine.loadedModelPath != model.filePath &&
            !sharedLoadingTarget)) {
      engine = LocalLlmEngine();
      _ownsLocalEngine = true;
    }
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
    final endpoint = requestUri.path.replaceFirst(RegExp(r'^/v1'), '');
    final base = config.baseUrl.trim();
    final trimmed =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
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
      request.headers
          .set('anthropic-version', ApiProtocolAdapter.anthropicVersion);
    } else {
      request.headers.set('Authorization', 'Bearer ${config.apiKey}');
    }
  }
}
