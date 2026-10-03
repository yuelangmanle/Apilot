import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/api_config.dart';
import 'api_protocol_adapter.dart';

class ModelListFetchResult {
  final List<String> models;
  final String? sourceUrl;
  final String? errorMessage;

  const ModelListFetchResult._({
    required this.models,
    required this.sourceUrl,
    required this.errorMessage,
  });

  const ModelListFetchResult.success({
    required List<String> models,
    required String sourceUrl,
  }) : this._(
          models: models,
          sourceUrl: sourceUrl,
          errorMessage: null,
        );

  const ModelListFetchResult.failure(String message)
      : this._(
          models: const [],
          sourceUrl: null,
          errorMessage: message,
        );

  bool get isSuccess => errorMessage == null;
}

/// 可被界面或 Agent 取消的请求信号。
///
/// `sendRequestStream` 收到信号后会停止消费响应并释放 HTTP 连接，避免
/// 停止按钮只停 UI、后台请求仍继续占用网络和服务端生成额度。
class ApiRequestCancellation {
  bool _cancelled = false;
  Completer<void>? _completer;
  void Function()? _cancelHandler;

  bool get isCancelled => _cancelled;

  Future<void> get whenCancelled {
    if (_cancelled) return Future<void>.value();
    return (_completer ??= Completer<void>()).future;
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelHandler?.call();
    final completer = _completer;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void setCancelHandler(void Function() handler) {
    _cancelHandler = handler;
    if (_cancelled) handler();
  }
}

class ApiService {
  /// 模块级共享连接池：体检 N 个 Key 复用 TLS 连接而非 N 次握手。
  static final http.Client _sharedClient = http.Client();

  /// 智能拼接 URL，避免重复路径段
  static String buildUrl(String baseUrl, String endpoint) {
    String base = baseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    String ep = endpoint.trim();
    if (ep.isEmpty) return base;
    if (!ep.startsWith('/')) ep = '/$ep';

    // 提取 base 的路径部分
    final baseUri = Uri.parse(base);
    final basePath = baseUri.path; // e.g. "/v1"

    // 如果 endpoint 以 basePath 结尾，说明重复了，去掉
    // 例如 base="/v1", endpoint="/v1/chat/completions" → 只用 base + "/chat/completions"
    if (basePath.isNotEmpty && ep.startsWith(basePath)) {
      final remainder = ep.substring(basePath.length);
      if (remainder.isEmpty || remainder.startsWith('/')) {
        return '$base$remainder';
      }
    }

    return '$base$ep';
  }

  /// 验证API是否有效
  Future<Map<String, dynamic>> validateApi(ApiConfig apiConfig) async {
    try {
      final models = await getAvailableModels(apiConfig);
      if (models.isNotEmpty) {
        return {
          'valid': true,
          'message': 'API有效，发现 ${models.length} 个模型',
          'models': models,
        };
      }

      final testResult = await _testConnection(apiConfig);
      return testResult;
    } catch (e) {
      return {
        'valid': false,
        'message': 'API验证失败: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _testConnection(ApiConfig apiConfig) async {
    try {
      String baseUrl = apiConfig.baseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      final uri = Uri.parse(baseUrl);
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiConfig.apiKey}',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 500) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          return {
            'valid': false,
            'message': '服务器拒绝了请求（状态码 ${response.statusCode}），请检查 API Key 是否正确',
          };
        }
        return {
          'valid': true,
          'message': 'API可达，状态码: ${response.statusCode}',
        };
      }
      return {
        'valid': false,
        'message': 'API返回错误，状态码: ${response.statusCode}',
      };
    } catch (e) {
      return {
        'valid': false,
        'message': '无法连接到API: $e',
      };
    }
  }

  Future<List<String>> getAvailableModels(ApiConfig apiConfig) async {
    return (await fetchAvailableModels(apiConfig)).models;
  }

  Future<ModelListFetchResult> fetchAvailableModels(ApiConfig apiConfig) async {
    try {
      String baseUrl = apiConfig.baseUrl.trim();
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      List<String> urlsToTry = [];

      if (baseUrl.endsWith('/models')) {
        urlsToTry.add(baseUrl);
      } else {
        if (baseUrl.endsWith('/v1') ||
            baseUrl.endsWith('/v2') ||
            baseUrl.endsWith('/v3')) {
          urlsToTry.add('$baseUrl/models');
        }
        urlsToTry.add('$baseUrl/v1/models');
        urlsToTry.add('$baseUrl/models');
      }

      String? lastError;
      for (final modelsUrl in urlsToTry) {
        try {
          final uri = Uri.parse(modelsUrl);
          final response = await _sharedClient
              .get(
                uri,
                headers: ApiProtocolAdapter.authHeaders(
                  protocolId: apiConfig.protocolId,
                  apiKey: apiConfig.apiKey,
                ),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode != 200) {
            lastError = '$modelsUrl 返回状态码 ${response.statusCode}';
            continue;
          }

          final models = _parseModels(jsonDecode(response.body));
          if (models != null) {
            return ModelListFetchResult.success(
              models: models,
              sourceUrl: modelsUrl,
            );
          }
          lastError = '$modelsUrl 未返回可识别的模型列表';
        } catch (e) {
          lastError = '$modelsUrl 请求失败: $e';
          continue;
        }
      }

      return ModelListFetchResult.failure(lastError ?? '未获取到模型列表');
    } catch (e) {
      return ModelListFetchResult.failure('获取模型列表失败: $e');
    }
  }

  List<String>? _parseModels(Object? data) {
    final Object? modelsList;
    if (data is Map && data['data'] is List) {
      modelsList = data['data'];
    } else if (data is Map && data['models'] is List) {
      modelsList = data['models'];
    } else if (data is List) {
      modelsList = data;
    } else {
      return null;
    }

    final models = <String>[];
    for (final item in modelsList as List) {
      final model = item is Map
          ? (item['id'] ?? item['name'])?.toString()
          : item?.toString();
      final trimmed = model?.trim();
      if (trimmed != null && trimmed.isNotEmpty && !models.contains(trimmed)) {
        models.add(trimmed);
      }
    }
    return models;
  }

  Future<Map<String, dynamic>> sendRequest({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
  }) {
    return _sendRequest(
      apiConfig: apiConfig,
      model: model,
      endpoint: endpoint,
      requestBody: requestBody,
      includeHeaders: false,
    );
  }

  /// 发送请求并返回完整响应（包含headers）
  Future<Map<String, dynamic>> sendRequestWithHeaders({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
  }) {
    return _sendRequest(
      apiConfig: apiConfig,
      model: model,
      endpoint: endpoint,
      requestBody: requestBody,
      includeHeaders: true,
    );
  }

  Future<Map<String, dynamic>> _sendRequest({
    required ApiConfig apiConfig,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
    required bool includeHeaders,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final effectiveEndpoint = endpoint.trim().isEmpty
          ? ApiProtocolAdapter.defaultChatEndpoint(
              apiConfig.baseUrl, apiConfig.protocolId)
          : endpoint;
      final url = buildUrl(apiConfig.baseUrl, effectiveEndpoint);
      final uri = Uri.parse(url);

      // 确保 model 在请求体中，并按协议转换请求体。
      final body = Map<String, dynamic>.from(requestBody);
      if (!body.containsKey('model')) {
        body['model'] = model;
      }
      final protocolBody = ApiProtocolAdapter.requestBodyFor(
        body,
        apiConfig.protocolId,
      );
      // Key 池：健康优先的候选序列，首发即避开已知失效的 Key。
      // 不能固定使用主 Key：如果它上一次已经失败，后面的故障转移索引
      // 会和实际发出的 Key 错位，导致把备用 Key 错记为失败。
      final candidates = KeyPool.candidates(apiConfig);
      final initialKey =
          candidates.isEmpty ? apiConfig.apiKey : candidates.first;
      var candidateIndex = 0;
      var currentKey = initialKey;

      http.Response response = await http
          .post(
            uri,
            headers: ApiProtocolAdapter.authHeaders(
              protocolId: apiConfig.protocolId,
              apiKey: initialKey,
            ),
            body: jsonEncode(protocolBody),
          )
          .timeout(const Duration(seconds: 60));

      // 401/403 自动切换下一把候选 Key 重试。
      while (response.statusCode == 401 || response.statusCode == 403) {
        KeyPool.markFailed(apiConfig.id, currentKey);
        candidateIndex++;
        if (candidateIndex >= candidates.length) break;
        final nextKey = candidates[candidateIndex];
        currentKey = nextKey;
        response = await http
            .post(
              uri,
              headers: ApiProtocolAdapter.authHeaders(
                protocolId: apiConfig.protocolId,
                apiKey: nextKey,
              ),
              body: jsonEncode(protocolBody),
            )
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 401 && response.statusCode != 403) {
          KeyPool.markHealthy(apiConfig.id, nextKey);
        }
      }
      if (response.statusCode != 401 && response.statusCode != 403) {
        KeyPool.markHealthy(apiConfig.id, currentKey);
      }

      stopwatch.stop();

      Map<String, dynamic> responseBody;
      try {
        responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        responseBody = {'raw': response.body};
      }

      final result = <String, dynamic>{
        'statusCode': response.statusCode,
        'body': responseBody,
        'duration': stopwatch.elapsedMilliseconds,
      };
      if (includeHeaders) {
        result['headers'] = Map<String, String>.from(response.headers);
      }
      return result;
    } catch (e) {
      stopwatch.stop();
      rethrow;
    }
  }

  /// 流式发送聊天请求：逐帧产出增量文本，结束时给出完整归一化响应
  /// （choices/usage 形状，兼容历史记录与响应查看器）。
  Stream<StreamChatEvent> sendRequestStream({
    required ApiConfig apiConfig,
    required String model,
    required Map<String, dynamic> requestBody,
    bool includeUsage = true,
    bool Function()? shouldStop,
    ApiRequestCancellation? cancellation,
  }) async* {
    final protocolId = apiConfig.protocolId;
    final endpoint = ApiProtocolAdapter.defaultChatEndpoint(
      apiConfig.baseUrl,
      protocolId,
    );
    final url = buildUrl(apiConfig.baseUrl, endpoint);
    final uri = Uri.parse(url);

    final body = Map<String, dynamic>.from(requestBody);
    if (!body.containsKey('model')) {
      body['model'] = model;
    }
    body['stream'] = true;
    if (includeUsage && !ApiProtocolAdapter.isAnthropic(protocolId)) {
      body['stream_options'] = {'include_usage': true};
    }
    final protocolBody = ApiProtocolAdapter.requestBodyFor(body, protocolId);

    final candidates = KeyPool.candidates(apiConfig);
    final initialKey = candidates.isEmpty ? apiConfig.apiKey : candidates.first;
    var candidateIndex = 0;
    var currentKey = initialKey;
    final request = http.Request('POST', uri)
      ..headers.addAll(ApiProtocolAdapter.authHeaders(
        protocolId: protocolId,
        apiKey: initialKey,
      ))
      ..body = jsonEncode(protocolBody);

    final stopwatch = Stopwatch()..start();
    final client = http.Client();
    cancellation?.setCancelHandler(client.close);
    try {
      if (cancellation?.isCancelled == true) return;
      final sendFuture =
          client.send(request).timeout(const Duration(seconds: 30));
      final sendResult = cancellation == null
          ? await sendFuture
          : await Future.any<Object?>([
              sendFuture,
              cancellation.whenCancelled.then<Object?>((_) => null),
            ]);
      if (sendResult == null) return;
      var response = sendResult as http.StreamedResponse;
      // 流式故障转移：候选 Key 依次重试（非 200 时）。
      while (response.statusCode == 401 || response.statusCode == 403) {
        await response.stream.drain<void>();
        KeyPool.markFailed(apiConfig.id, currentKey);
        candidateIndex++;
        if (candidateIndex >= candidates.length) break;
        final nextKey = candidates[candidateIndex];
        currentKey = nextKey;
        final retry = http.Request('POST', uri)
          ..headers.addAll(ApiProtocolAdapter.authHeaders(
            protocolId: protocolId,
            apiKey: nextKey,
          ))
          ..body = jsonEncode(protocolBody);
        response =
            await client.send(retry).timeout(const Duration(seconds: 30));
        if (response.statusCode != 401 && response.statusCode != 403) {
          KeyPool.markHealthy(apiConfig.id, nextKey);
        }
      }
      if (response.statusCode != 401 && response.statusCode != 403) {
        KeyPool.markHealthy(apiConfig.id, currentKey);
      }
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw ApiException(statusCode: response.statusCode, body: errorBody);
      }

      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      TokenUsage? usage;
      var rawChunks = 0;

      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != 'text/event-stream') {
        final rawBody = await response.stream.bytesToString();
        final decoded = jsonDecode(rawBody);
        if (decoded is! Map) {
          throw const FormatException('非流式响应不是 JSON 对象');
        }
        final responseBody = Map<String, dynamic>.from(decoded);
        final text = ApiProtocolAdapter.extractAssistantText(
          responseBody,
          protocolId,
        );
        if (text != null && text.isNotEmpty) {
          contentBuffer.write(text);
          yield StreamChatEvent.delta(text);
        }
        usage = ApiProtocolAdapter.extractUsage(responseBody, protocolId);
        stopwatch.stop();
        yield StreamChatEvent.done(
          {
            'body': responseBody,
            'model': responseBody['model'] ?? model,
            'stream': false,
          },
          durationMs: stopwatch.elapsedMilliseconds,
          usage: usage,
        );
        return;
      }

      final lines = response.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter());
      // SSE 规范：一个事件可由多行 data: 组成，空行表示事件结束。
      var dataBuffer = StringBuffer();
      var receivedDone = false;
      var interrupted = false;

      StreamChatEvent? parseDataFrame(String data) {
        if (data.isEmpty) return null;
        if (data == '[DONE]') {
          receivedDone = true;
          return null;
        }
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map<String, dynamic>) return null;
          rawChunks++;
          final parsed = SseStreamParser.parseFrame(decoded, protocolId);
          final text = parsed.deltaText ?? parsed.reasoningDelta;
          if (text != null && text.isNotEmpty) {
            if (parsed.isReasoning) {
              reasoningBuffer.write(text);
            } else {
              contentBuffer.write(text);
            }
          }
          if (parsed.usage != null) {
            // Anthropic 的 message_start 带完整 input/output，后续
            // message_delta 只带累计 output，字段级合并以免丢 prompt。
            final incoming = parsed.usage!;
            usage = TokenUsage(
              promptTokens: incoming.promptTokens ?? usage?.promptTokens,
              completionTokens:
                  incoming.completionTokens ?? usage?.completionTokens,
              cachedTokens: incoming.cachedTokens ?? usage?.cachedTokens,
              reasoningTokens:
                  incoming.reasoningTokens ?? usage?.reasoningTokens,
            );
          }
          if (text == null || text.isEmpty) return null;
          return parsed.isReasoning
              ? StreamChatEvent.reasoning(text)
              : StreamChatEvent.delta(text);
        } on FormatException catch (e) {
          // 单帧解析失败只跳过该帧（代理保活行/截断 JSON），不废整条流。
          debugPrint('[Stream] 坏帧跳过: $e');
          return null;
        }
      }

      final iterator = StreamIterator<String>(lines);
      while (true) {
        if (shouldStop?.call() == true || cancellation?.isCancelled == true) {
          interrupted = true;
          await iterator.cancel();
          break;
        }
        final moveNext = iterator.moveNext();
        final hasLine = cancellation == null
            ? await moveNext
            : await Future.any<bool>([
                moveNext,
                cancellation.whenCancelled.then<bool>((_) => false),
              ]);
        if (!hasLine || cancellation?.isCancelled == true) {
          interrupted = cancellation?.isCancelled == true;
          await iterator.cancel();
          break;
        }
        final line = iterator.current;
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          if (dataBuffer.isEmpty) continue;
        } else if (trimmed.startsWith(':')) {
          continue;
        } else if (trimmed.startsWith('data:')) {
          dataBuffer.writeln(trimmed.substring(5).trim());
          continue;
        } else {
          continue;
        }

        final data = dataBuffer.toString().trimRight();
        dataBuffer = StringBuffer();
        final event = parseDataFrame(data);
        if (event != null) yield event;
        if (receivedDone) break;
      }

      if (interrupted || shouldStop?.call() == true) return;

      // 部分代理会在最后一个 data: 帧后直接关闭连接，没有 SSE 空行。
      if (!receivedDone && dataBuffer.isNotEmpty) {
        final event = parseDataFrame(dataBuffer.toString().trimRight());
        if (event != null) yield event;
      }
      stopwatch.stop();

      final normalized = <String, dynamic>{
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': contentBuffer.toString(),
            },
            'finish_reason': 'stop',
          }
        ],
        'model': model,
        'stream': true,
        if (usage case final currentUsage?)
          'usage': {
            'prompt_tokens': currentUsage.promptTokens,
            'completion_tokens': currentUsage.completionTokens,
            'total_tokens': currentUsage.totalTokens,
          },
        if (rawChunks == 0) 'raw': '流式响应为空',
      };
      yield StreamChatEvent.done(
        normalized,
        durationMs: stopwatch.elapsedMilliseconds,
        usage: usage,
      );
    } finally {
      client.close();
    }
  }
}

/// 流式请求的事件：delta 增量 / reasoning 推理增量 / done 终态。
class StreamChatEvent {
  final String? delta;
  final String? reasoning;
  final Map<String, dynamic>? response;
  final int? durationMs;
  final TokenUsage? usage;

  const StreamChatEvent.delta(this.delta)
      : reasoning = null,
        response = null,
        durationMs = null,
        usage = null;

  const StreamChatEvent.reasoning(this.reasoning)
      : delta = null,
        response = null,
        durationMs = null,
        usage = null;

  const StreamChatEvent.done(this.response,
      {required this.durationMs, required this.usage})
      : delta = null,
        reasoning = null;

  bool get isDone => response != null;
}

/// 非 200 的协议层错误，便于界面区分鉴权失败等场景。
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException({required this.statusCode, required this.body});

  @override
  String toString() => 'API 返回 $statusCode: '
      '${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
}

/// Key 池：每个配置可挂多把备用 Key（metadata.extraKeys）。
/// 主 Key 401/403 时自动切换；运行时记忆失败过的 Key，优先用健康的。
class KeyPool {
  KeyPool._();

  static final Map<String, Set<String>> _failedKeys = {};

  static List<String> extraKeys(ApiConfig config) {
    final extras = config.metadata?['extraKeys'];
    if (extras is! List) return const [];
    return extras
        .whereType<String>()
        .where((k) => k.trim().isNotEmpty)
        .map((k) => k.trim())
        .toList();
  }

  static void markFailed(String configId, String key) {
    _failedKeys.putIfAbsent(configId, () => {}).add(key);
  }

  static void markHealthy(String configId, String key) {
    _failedKeys[configId]?.remove(key);
  }

  /// 返回按健康优先排序的候选 Key（含主 Key），供请求发起前选择。
  static List<String> candidates(ApiConfig config) {
    final all = [config.apiKey, ...extraKeys(config)]
        .where((key) => key.trim().isNotEmpty)
        .toSet()
        .toList();
    final failed = _failedKeys[config.id] ?? const {};
    final healthy = all.where((k) => !failed.contains(k)).toList();
    final dead = all.where((k) => failed.contains(k)).toList();
    return [...healthy, ...dead];
  }
}
