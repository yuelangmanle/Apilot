import 'package:api_manager/features/api_management/services/api_config_export_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfigExportFormatter', () {
    test('toCurl appends chat/completions to a v1 base URL', () {
      final curl = ApiConfigExportFormatter.toCurl(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        model: 'deepseek-chat',
      );

      expect(
          curl,
          contains(
              "curl 'https://api.deepseek.com/v1/chat/completions'"));
      expect(curl, contains("Authorization: Bearer sk-test"));
      expect(curl, contains('"model": "deepseek-chat"'));
    });

    test('toCurl avoids duplicating an endpoint already present', () {
      final curl = ApiConfigExportFormatter.toCurl(
        baseUrl: 'https://example.com/api/v1/chat/completions',
        apiKey: 'sk-test',
        model: 'm',
      );

      expect(curl.contains('chat/completions/chat/completions'), isFalse);
      expect(curl, startsWith("curl 'https://example.com/api/v1/chat/completions'"));
    });

    test('toEnv produces upper-case snake keys and skips empty models', () {
      final env = ApiConfigExportFormatter.toEnv(
        name: 'My DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-abc',
        model: null,
      );

      expect(env, contains('MY_DEEPSEEK_BASE_URL="https://api.deepseek.com/v1"'));
      expect(env, contains('MY_DEEPSEEK_API_KEY="sk-abc"'));
      expect(env.contains('_MODEL='), isFalse);
    });

    test('toEnv yields a valid identifier for non-ascii-only names', () {
      final env = ApiConfigExportFormatter.toEnv(
        name: '测试',
        baseUrl: 'https://x.com/v1',
        apiKey: 'k',
        model: 'm',
      );

      final keyLine =
          env.split('\n').firstWhere((line) => line.contains('_API_KEY='));
      final key = keyLine.split('=')[0].replaceFirst('export ', '');
      expect(RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key), isTrue,
          reason: 'env key 应该是合法标识符: $key');
    });

    test('toEnv keeps a model line when a model is provided', () {
      final env = ApiConfigExportFormatter.toEnv(
        name: 'openrouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'sk-or',
        model: 'anthropic/claude-3.5-sonnet',
      );

      expect(env,
          contains('OPENROUTER_MODEL="anthropic/claude-3.5-sonnet"'));
    });

    test('OpenAI snippet uses the supplied base URL and model', () {
      final snippet = ApiConfigExportFormatter.toOpenAiClientSnippet(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-x',
        model: 'gpt-4o-mini',
      );

      expect(snippet, contains('base_url="https://api.example.com/v1"'));
      expect(snippet, contains('model="gpt-4o-mini"'));
    });
  });
}
