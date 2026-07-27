import 'package:api_manager/core/services/api_profile_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiProfileRegistry', () {
    test('preserves an explicit DeepSeek provider and protocol', () {
      final profile = ApiProfileRegistry.resolve(
        baseUrl: 'https://gateway.example.com/v1',
        providerId: 'deepseek',
        protocolId: 'openai_compatible',
      );

      expect(profile.providerId, 'deepseek');
      expect(profile.protocolId, 'openai_compatible');
      expect(profile.providerDisplayName, 'DeepSeek');
    });

    test('infers DeepSeek from its official endpoint', () {
      final profile = ApiProfileRegistry.resolve(
        baseUrl: 'https://api.deepseek.com/v1',
      );

      expect(profile.providerId, 'deepseek');
      expect(profile.protocolId, 'openai_compatible');
    });

    test('uses custom OpenAI-compatible semantics for an unknown endpoint', () {
      final profile = ApiProfileRegistry.resolve(
        baseUrl: 'https://llm.example.com/v1',
      );

      expect(profile.providerId, 'custom');
      expect(profile.protocolId, 'openai_compatible');
      expect(profile.providerDisplayName, '自定义服务');
    });

    test('normalizes an unsupported explicit provider to custom', () {
      final profile = ApiProfileRegistry.resolve(
        baseUrl: 'https://gateway.example.com/v1',
        providerId: 'unregistered_provider',
      );

      expect(profile.providerId, 'custom');
      expect(profile.protocolId, 'openai_compatible');
    });
  });
}
