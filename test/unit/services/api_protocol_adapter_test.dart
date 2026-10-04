import 'package:api_manager/core/services/api_protocol_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiProtocolAdapter.authHeaders', () {
    test('openai-compatible uses Bearer', () {
      final headers = ApiProtocolAdapter.authHeaders(
        protocolId: 'openai_compatible',
        apiKey: 'sk-abc',
      );
      expect(headers['Authorization'], 'Bearer sk-abc');
      expect(headers.containsKey('x-api-key'), isFalse);
    });

    test('anthropic uses x-api-key + anthropic-version', () {
      final headers = ApiProtocolAdapter.authHeaders(
        protocolId: 'anthropic_messages',
        apiKey: 'sk-ant',
      );
      expect(headers['x-api-key'], 'sk-ant');
      expect(headers['anthropic-version'], ApiProtocolAdapter.anthropicVersion);
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('ApiProtocolAdapter.requestBodyFor', () {
    test('openai bodies pass through unchanged', () {
      final body = {
        'model': 'gpt-4o',
        'messages': [
          {'role': 'system', 'content': 'be brief'},
          {'role': 'user', 'content': 'hi'},
        ],
        'temperature': 0.5,
      };
      expect(
        ApiProtocolAdapter.requestBodyFor(body, 'openai_compatible'),
        equals(body),
      );
    });

    test('anthropic bodies extract system and default max_tokens', () {
      final converted = ApiProtocolAdapter.requestBodyFor(
        {
          'model': 'claude-sonnet-4-5',
          'messages': [
            {'role': 'system', 'content': 'be brief'},
            {'role': 'user', 'content': 'hi'},
          ],
          'temperature': 0.5,
        },
        'anthropic_messages',
      );

      expect(converted['system'], 'be brief');
      expect(converted['max_tokens'], 1024);
      expect(converted['temperature'], 0.5);
      final messages = converted['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.single)['role'], 'user');
      // OpenAI 专有字段不应透传给 Anthropic。
      expect(converted.containsKey('stream_options'), isFalse);
    });

    test('anthropic bodies respect an explicit max_tokens', () {
      final converted = ApiProtocolAdapter.requestBodyFor(
        {
          'model': 'claude-sonnet-4-5',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 2048,
        },
        'anthropic_messages',
      );
      expect(converted['max_tokens'], 2048);
    });

    test('anthropic converts OpenAI image blocks to base64 image sources', () {
      final converted = ApiProtocolAdapter.requestBodyFor(
        {
          'model': 'claude-sonnet',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '看这张图'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,aGVsbG8=',
                  },
                },
              ],
            },
          ],
          'max_tokens': 256,
        },
        'anthropic_messages',
      );

      final blocks = (converted['messages'] as List).single['content'] as List;
      expect(blocks[0], {'type': 'text', 'text': '看这张图'});
      expect(blocks[1], {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/png',
          'data': 'aGVsbG8=',
        },
      });
    });
  });

  group('ApiProtocolAdapter.extractAssistantText', () {
    test('extracts text from content block arrays', () {
      expect(
        ApiProtocolAdapter.extractAssistantText(
          {
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '页面已完成'},
                    {'type': 'output_text', 'text': '，可预览。'},
                  ],
                },
              },
            ],
          },
          'openai_compatible',
        ),
        '页面已完成，可预览。',
      );
    });
  });

  group('ApiProtocolAdapter.defaultChatEndpoint', () {
    test('anthropic resolves /messages on a v1 base', () {
      expect(
        ApiProtocolAdapter.defaultChatEndpoint(
            'https://api.anthropic.com/v1', 'anthropic_messages'),
        '/messages',
      );
      expect(
        ApiProtocolAdapter.defaultChatEndpoint(
            'https://api.anthropic.com', 'anthropic_messages'),
        '/v1/messages',
      );
    });

    test('openai-compatible keeps /chat/completions', () {
      expect(
        ApiProtocolAdapter.defaultChatEndpoint(
            'https://api.deepseek.com/v1', 'openai_compatible'),
        '/chat/completions',
      );
    });

    test('openai-compatible exposes the independent file upload endpoint', () {
      expect(
        ApiProtocolAdapter.defaultFileUploadEndpoint('openai_compatible'),
        '/files',
      );
      expect(
        ApiProtocolAdapter.defaultFileUploadEndpoint('anthropic_messages'),
        isNull,
      );
    });
  });

  group('ApiProtocolAdapter.extractUsage', () {
    test('maps anthropic input/output tokens', () {
      final usage = ApiProtocolAdapter.extractUsage(
        {
          'usage': {'input_tokens': 10, 'output_tokens': 25},
        },
        'anthropic_messages',
      );
      expect(usage?.promptTokens, 10);
      expect(usage?.completionTokens, 25);
      expect(usage?.totalTokens, 35);
    });

    test('maps openai prompt/completion tokens', () {
      final usage = ApiProtocolAdapter.extractUsage(
        {
          'usage': {'prompt_tokens': 7, 'completion_tokens': 3},
        },
        'openai_compatible',
      );
      expect(usage?.promptTokens, 7);
      expect(usage?.completionTokens, 3);
      expect(usage?.totalTokens, 10);
    });

    test('returns null for missing usage', () {
      expect(ApiProtocolAdapter.extractUsage({}, 'openai_compatible'), isNull);
      expect(
          ApiProtocolAdapter.extractUsage(null, 'openai_compatible'), isNull);
    });
  });

  group('SseStreamParser', () {
    test('parses OpenAI chunk deltas and terminal usage', () {
      final delta = SseStreamParser.parseFrame(
        {
          'choices': [
            {
              'delta': {'content': 'Hello'},
            }
          ],
        },
        'openai_compatible',
      );
      expect(delta.deltaText, 'Hello');

      final usageFrame = SseStreamParser.parseFrame(
        {
          'choices': [],
          'usage': {'prompt_tokens': 5, 'completion_tokens': 2},
        },
        'openai_compatible',
      );
      expect(usageFrame.deltaText, isNull);
      expect(usageFrame.usage?.totalTokens, 7);
    });

    test('parses Anthropic content_block_delta and message_delta usage', () {
      final delta = SseStreamParser.parseFrame(
        {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'Bonjour'},
        },
        'anthropic_messages',
      );
      expect(delta.deltaText, 'Bonjour');

      final usage = SseStreamParser.parseFrame(
        {
          'type': 'message_delta',
          'usage': {'output_tokens': 42},
        },
        'anthropic_messages',
      );
      expect(usage.usage?.completionTokens, 42);
    });

    test('parses Anthropic message_start input tokens', () {
      final start = SseStreamParser.parseFrame(
        {
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 11},
          },
        },
        'anthropic_messages',
      );
      expect(start.usage?.promptTokens, 11);
    });
  });
}
