/// 协议适配层：按 `protocolId` 生成鉴权头、默认端点、请求体与
/// 响应归一化。此前全项目只有 OpenAI Bearer 一种实现，导致
/// Anthropic 模板添加即 401。
class ApiProtocolAdapter {
  const ApiProtocolAdapter._();

  static const String anthropicVersion = '2023-06-01';

  /// 是否使用 Anthropic Messages 协议（x-api-key + anthropic-version）。
  static bool isAnthropic(String protocolId) =>
      protocolId == 'anthropic_messages';

  /// Google GenAI 与 OpenAI 兼容协议都走 Bearer：
  /// Gemini 官方提供 OpenAI 兼容层（/v1beta/openai）。
  static bool isBearer(String protocolId) => !isAnthropic(protocolId);

  /// 请求头。openai/google_genai → Bearer；anthropic → x-api-key。
  static Map<String, String> authHeaders({
    required String protocolId,
    required String apiKey,
  }) {
    if (isAnthropic(protocolId)) {
      return {
        'x-api-key': apiKey,
        'anthropic-version': anthropicVersion,
        'Content-Type': 'application/json',
      };
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
  }

  /// 补全聊天端点：Anthropic 用 /messages（OpenAI 用 /chat/completions）。
  static String defaultChatEndpoint(String baseUrl, String protocolId) {
    if (!isAnthropic(protocolId)) return '/chat/completions';
    final base = baseUrl.trim();
    if (base.endsWith('/v1') ||
        base.endsWith('/v2') ||
        base.endsWith('/v3')) {
      return '/messages';
    }
    return '/v1/messages';
  }

  /// OpenAI 形状的请求体 → 协议原生请求体。
  /// Anthropic：system 提取为顶层字段、max_tokens 必填（默认 1024）。
  static Map<String, dynamic> requestBodyFor(
    Map<String, dynamic> openAiBody,
    String protocolId,
  ) {
    if (!isAnthropic(protocolId)) {
      return Map<String, dynamic>.from(openAiBody);
    }
    final messages = (openAiBody['messages'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final systemParts = <String>[];
    final chatMessages = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message['role'] == 'system') {
        final content = message['content'];
        if (content is String && content.isNotEmpty) systemParts.add(content);
        continue;
      }
      chatMessages.add(message);
    }
    return {
      'model': openAiBody['model'],
      'messages': chatMessages,
      if (systemParts.isNotEmpty) 'system': systemParts.join('\n'),
      'max_tokens': openAiBody['max_tokens'] ?? 1024,
      ..._withoutKeys(openAiBody, const {
        'model',
        'messages',
        'max_tokens',
        'stream',
        'stream_options',
      }),
    };
  }

  /// 从协议原生响应中取出助手文本（供流式组装/展示兜底）。
  static String? extractAssistantText(
    Map<String, dynamic> response,
    String protocolId,
  ) {
    if (!isAnthropic(protocolId)) {
      final choices = response['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final message = first['message'];
      if (message is Map) return message['content']?.toString();
      return null;
    }
    final content = response['content'];
    if (content is! List) return null;
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text']?.toString() ?? '');
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }

  static TokenUsage? extractUsage(
    Map<String, dynamic>? response,
    String protocolId,
  ) {
    if (response == null) return null;
    final usage = response['usage'];
    if (usage is! Map) return null;
    if (isAnthropic(protocolId)) {
      return TokenUsage(
        promptTokens: _asInt(usage['input_tokens']),
        completionTokens: _asInt(usage['output_tokens']),
      );
    }
    return TokenUsage(
      promptTokens: _asInt(usage['prompt_tokens']),
      completionTokens: _asInt(usage['completion_tokens']),
    );
  }

  static Map<String, dynamic> _withoutKeys(
    Map<String, dynamic> source,
    Set<String> keys,
  ) {
    return {
      for (final entry in source.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
  }

  static int? _asInt(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : null);
}

/// 归一化后的 token 用量（两协议字段名不同）。
class TokenUsage {
  final int? promptTokens;
  final int? completionTokens;

  const TokenUsage({this.promptTokens, this.completionTokens});

  int? get totalTokens {
    final prompt = promptTokens;
    final completion = completionTokens;
    if (prompt == null && completion == null) return null;
    return (prompt ?? 0) + (completion ?? 0);
  }
}

/// 流式 SSE 解析：支持 OpenAI（chat.completion.chunk）与
/// Anthropic（content_block_delta / message_delta / message_start）。
class SseStreamParser {
  /// 输入一帧 SSE JSON，返回增量文本与 usage（可为空）。
  static StreamParseResult parseFrame(
    Map<String, dynamic> frame,
    String protocolId,
  ) {
    if (ApiProtocolAdapter.isAnthropic(protocolId)) {
      return _parseAnthropicFrame(frame);
    }
    return _parseOpenAiFrame(frame);
  }

  static StreamParseResult _parseOpenAiFrame(Map<String, dynamic> frame) {
    String? delta;
    final choices = frame['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final deltaMap = first['delta'];
        if (deltaMap is Map && deltaMap['content'] is String) {
          delta = deltaMap['content'] as String;
        }
      }
    }
    return StreamParseResult(
      deltaText: delta,
      usage: ApiProtocolAdapter.extractUsage(frame, 'openai_compatible'),
    );
  }

  static StreamParseResult _parseAnthropicFrame(Map<String, dynamic> frame) {
    final type = frame['type'];
    String? delta;
    TokenUsage? usage;
    if (type == 'content_block_delta') {
      final deltaMap = frame['delta'];
      if (deltaMap is Map && deltaMap['text'] is String) {
        delta = deltaMap['text'] as String;
      }
    } else if (type == 'message_start') {
      final message = frame['message'];
      if (message is Map) {
        usage = ApiProtocolAdapter.extractUsage(
          {'usage': message['usage']},
          'anthropic_messages',
        );
      }
    } else if (type == 'message_delta') {
      usage = ApiProtocolAdapter.extractUsage(frame, 'anthropic_messages');
    }
    return StreamParseResult(deltaText: delta, usage: usage);
  }
}

class StreamParseResult {
  final String? deltaText;
  final TokenUsage? usage;

  const StreamParseResult({this.deltaText, this.usage});
}
