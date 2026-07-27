import 'package:api_manager/features/api_management/services/api_connection_paste_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConnectionPasteParser', () {
    test('extracts key and URL from a JSON connection record', () {
      final result = ApiConnectionPasteParser.parse('''
        {"_type":"newapi_channel_conn","key":"test_key_123","url":"https://api.example.com/v1"}
      ''');

      expect(result, isNotNull);
      expect(result!.apiKey, 'test_key_123');
      expect(result.baseUrl, 'https://api.example.com/v1');
      expect(result.urlWasNormalized, isFalse);
    });

    test('prefers an explicit API key over an unrelated generic key', () {
      final result = ApiConnectionPasteParser.parse('''
        {
          "url": "https://api.example.com/v1",
          "key": "unrelated-metadata",
          "apiKey": "preferred-api-key-123"
        }
      ''');

      expect(result, isNotNull);
      expect(result!.apiKey, 'preferred-api-key-123');
    });

    test('normalizes a URL whose scheme separator is missing', () {
      final result = ApiConnectionPasteParser.parse('''
        {"key":"test_key_456","url":"http//broken.example.com"}
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'http://broken.example.com');
      expect(result.urlWasNormalized, isTrue);
    });

    test('extracts conventional environment variable assignments', () {
      final result = ApiConnectionPasteParser.parse('''
        OPENAI_BASE_URL=https://gateway.example.com/v1
        OPENAI_API_KEY=sk-test-789
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'sk-test-789');
    });

    test('extracts nested values from a long mixed JSON document', () {
      final result = ApiConnectionPasteParser.parse('''
        This heading and these notes are not part of the configuration.
        {
          "channel": {
            "metadata": {"owner": "example"},
            "credentials": {
              "apiKey": "long-test-key-0123456789",
              "endpoint": "https://proxy.example.com/openai/v1"
            }
          }
        }
        trailing text can be arbitrarily long too.
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://proxy.example.com/openai/v1');
      expect(result.apiKey, 'long-test-key-0123456789');
    });

    test('finds a valid JSON object after unrelated brace-delimited prose', () {
      final result = ApiConnectionPasteParser.parse('''
        以下只是说明文字，不是配置：{ this is not JSON }。

        请使用下面这一段连接信息：
        {"connection":{"baseURL":"https://gateway.example.com/v1","apiKey":"mixed-json-key-123"}}

        其他很长的说明文字也不应影响识别。
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'mixed-json-key-123');
    });

    test('extracts JavaScript-style configuration with variable field names',
        () {
      final result = ApiConnectionPasteParser.parse('''
        const clientOptions = {
          baseURL: 'https : //proxy.example.com/openai/v1',
          apiKey: 'javascript-style-key-456',
        };
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://proxy.example.com/openai/v1');
      expect(result.apiKey, 'javascript-style-key-456');
      expect(result.urlWasNormalized, isTrue);
    });

    test('extracts labels whose values are placed on following lines', () {
      final result = ApiConnectionPasteParser.parse('''
        接口地址
        <gateway.example.com/v1>

        X-API-Key
        multiline-labelled-key-789
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'multiline-labelled-key-789');
    });

    test('extracts Markdown labels with quoted values', () {
      final result = ApiConnectionPasteParser.parse('''
        ## Shared connection
        | API 地址 | `api.example.com/v1` |
        | 密钥 | `markdown-test-key` |
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://api.example.com/v1');
      expect(result.apiKey, 'markdown-test-key');
      expect(result.urlWasNormalized, isTrue);
    });

    test('extracts a cURL URL and Authorization bearer token', () {
      final result = ApiConnectionPasteParser.parse('''
        curl https://gateway.example.com/v1/chat/completions \\
          -H "Content-Type: application/json" \\
          -H "Authorization: Bearer curl-test-key"
      ''');

      expect(result, isNotNull);
      expect(
          result!.baseUrl, 'https://gateway.example.com/v1/chat/completions');
      expect(result.apiKey, 'curl-test-key');
    });

    test('keeps a nearby connection pair when a long text has an unrelated URL',
        () {
      final result = ApiConnectionPasteParser.parse('''
        下面的文档链接仅用于阅读，不是 API 配置：
        https://docs.example.com/integration/reference

        这里可能还有很多不相关的说明、示例和链接。

        Provider endpoint => "https://gateway.example.com/openai/v1"
        Access key => "nearby-config-key-012345"
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/openai/v1');
      expect(result.apiKey, 'nearby-config-key-012345');
    });

    test('removes YAML comments without changing the connection values', () {
      final result = ApiConnectionPasteParser.parse('''
        openai_base_url: "https://gateway.example.com/v1" # service endpoint
        openai_api_key: "yaml-comment-key-123" # keep private
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'yaml-comment-key-123');
    });

    test('extracts inline fields separated by arrows and Chinese punctuation',
        () {
      final result = ApiConnectionPasteParser.parse('''
        接口地址 -> https://gateway.example.com/v1；访问令牌 -> arrow-style-key-456
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'arrow-style-key-456');
    });

    test('extracts a JSON record escaped inside ordinary clipboard text', () {
      final result = ApiConnectionPasteParser.parse(r'''
        从聊天记录复制的内容：{\"base_url\":\"https://gateway.example.com/v1\",\"api_key\":\"escaped-json-key-789\"}
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'escaped-json-key-789');
    });

    test('does not impose a length cap on a text connection record', () {
      final notes = List<String>.filled(8192, '这是不相关的说明。').join();
      final result = ApiConnectionPasteParser.parse('''
        $notes
        API URL = https://gateway.example.com/v1
        API Key = long-text-key-0123456789
      ''');

      expect(result, isNotNull);
      expect(result!.baseUrl, 'https://gateway.example.com/v1');
      expect(result.apiKey, 'long-text-key-0123456789');
    });

    test('does not treat a placeholder variable as an API key', () {
      expect(
        ApiConnectionPasteParser.parse('''
          API_BASE_URL=https://api.example.com/v1
          API_KEY=\${API_KEY}
        '''),
        isNull,
      );
    });

    test('requires both a URL and key before returning a result', () {
      expect(
        ApiConnectionPasteParser.parse('https://api.example.com/v1'),
        isNull,
      );
      expect(
        ApiConnectionPasteParser.parse('API_KEY=test_key_only'),
        isNull,
      );
    });
  });
}
