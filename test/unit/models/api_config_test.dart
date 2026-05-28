import 'package:flutter_test/flutter_test.dart';
import 'package:api_manager/core/models/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('should create ApiConfig with required fields', () {
      final api = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      expect(api.id, '1');
      expect(api.name, 'DeepSeek');
      expect(api.baseUrl, 'https://api.deepseek.com');
      expect(api.apiKey, 'sk-test');
      expect(api.models, ['deepseek-chat']);
      expect(api.environment, 'development');
      expect(api.isFavorite, false);
      expect(api.group, isNull);
      expect(api.tags, isEmpty);
    });

    test('should convert to and from JSON', () {
      final api = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
        group: 'LLM',
        tags: ['llm', 'coding'],
        isFavorite: true,
      );

      final json = api.toJson();
      final fromJson = ApiConfig.fromJson(json);

      expect(fromJson.id, api.id);
      expect(fromJson.name, api.name);
      expect(fromJson.baseUrl, api.baseUrl);
      expect(fromJson.apiKey, api.apiKey);
      expect(fromJson.models, api.models);
      expect(fromJson.environment, api.environment);
      expect(fromJson.group, api.group);
      expect(fromJson.tags, api.tags);
      expect(fromJson.isFavorite, api.isFavorite);
    });
  });
}
