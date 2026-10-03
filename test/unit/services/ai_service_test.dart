import 'package:api_manager/core/services/ai/ai_service.dart';
import 'package:api_manager/core/services/local_llm/device_capabilities.dart';
import 'package:api_manager/core/services/local_llm/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiService.extractAssistantText', () {
    test('extracts OpenAI shape', () {
      final text = AiService.extractAssistantText({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '推荐 Q4_K_M'},
          }
        ],
      });
      expect(text, '推荐 Q4_K_M');
    });

    test('extracts Anthropic shape', () {
      final text = AiService.extractAssistantText({
        'content': [
          {'type': 'text', 'text': '使用 Q5_K_M'},
        ],
      });
      expect(text, '使用 Q5_K_M');
    });

    test('returns null for malformed bodies', () {
      expect(AiService.extractAssistantText(null), isNull);
      expect(AiService.extractAssistantText('raw string'), isNull);
      expect(AiService.extractAssistantText({}), isNull);
      expect(AiService.extractAssistantText({'choices': []}), isNull);
    });
  });

  group('AiService 路由', () {
    test('显式云端配置优先于全局本地开关', () {
      expect(
        AiService.resolveRoute(
          globalUseLocal: true,
          hasPreferredCloudConfig: true,
          localEngineLoaded: false,
        ),
        AiRoute.cloud,
      );
    });

    test('本地引擎优先于全局云端设置', () {
      expect(
        AiService.resolveRoute(
          globalUseLocal: false,
          hasPreferredCloudConfig: false,
          localEngineLoaded: true,
        ),
        AiRoute.local,
      );
    });
  });

  group('DeviceCapabilities', () {
    test('detect returns sane values', () async {
      final caps = await DeviceCapabilities.detect();
      expect(caps.ramMb, greaterThan(0));
      expect(caps.cpuCores, greaterThan(0));
      expect(caps.platform, isNotEmpty);
      expect(caps.summary, contains('内存约'));
    });
  });

  group('LocalModelCatalog.recommendForRam', () {
    test('returns only models that fit the RAM budget', () {
      // 2GB 设备只能装最小的（Gemma 1B 约 800MB + 800MB 开销）
      final small = LocalModelCatalog.recommendForRam(1700);
      expect(small.every((m) => m.sizeBytes / (1024 * 1024) + 800 <= 1700),
          isTrue);

      // 8GB 设备应该能装下多个
      final big = LocalModelCatalog.recommendForRam(8000);
      expect(big.length, greaterThanOrEqualTo(3));
    });

    test('findById locates built-in models', () {
      expect(LocalModelCatalog.findById('qwen3-4b-q4km'), isNotNull);
      expect(LocalModelCatalog.findById('nonexistent'), isNull);
    });
  });
}
