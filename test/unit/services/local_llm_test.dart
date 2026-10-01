import 'package:api_manager/core/services/local_llm/local_llm_engine.dart';
import 'package:llamadart/llamadart.dart';
import 'package:api_manager/core/services/local_llm/model_url_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalLlmEngine', () {
    test('starts unloaded and rejects generate before load', () async {
      final engine = LocalLlmEngine();
      expect(engine.isLoaded, isFalse);
      expect(
        () => engine.generate([
          const LlamaChatMessage.fromText(
              role: LlamaChatRole.user, text: 'hi'),
        ]),
        throwsStateError,
      );
      await engine.dispose();
    });

    test('dispose is idempotent', () async {
      final engine = LocalLlmEngine();
      await engine.dispose();
      await engine.dispose(); // 不应抛异常
      expect(engine.isLoaded, isFalse);
    });

    test('loadModel throws StateError after dispose', () async {
      final engine = LocalLlmEngine();
      await engine.dispose();
      expect(
        () => engine.loadModel('/nonexistent.gguf'),
        throwsStateError,
      );
    });
  });

  group('ModelUrlParser edge cases', () {
    test('parses HF tree URL with subdirectory', () {
      final result = ModelUrlParser.parse(
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/tree/main');
      expect(result.downloadUrls, isNotEmpty);
      expect(result.modelName, 'Qwen3-4B');
    });

    test('parses hf-mirror.com URL', () {
      final result = ModelUrlParser.parse(
          'https://hf-mirror.com/unsloth/Qwen3-4B-GGUF');
      expect(result.downloadUrls, isNotEmpty);
    });

    test('returns empty for non-model URLs', () {
      expect(ModelUrlParser.parse('https://google.com').isEmpty, isTrue);
      expect(ModelUrlParser.parse('https://github.com').isEmpty, isTrue);
    });

    test('extracts .gguf URL from mixed text', () {
      final result = ModelUrlParser.parse(
          'Download from https://example.com/models/qwen3-4b-q4km.gguf (4GB)');
      expect(result.downloadUrls, hasLength(1));
      expect(result.downloadUrls.first, contains('.gguf'));
    });

    test('direct .gguf download link passes through', () {
      final result = ModelUrlParser.parse(
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf');
      expect(result.downloadUrls, hasLength(1));
      expect(result.downloadUrls.first, contains('Q4_K_M'));
    });

    test('parses ModelScope page', () {
      final result = ModelUrlParser.parse(
          'https://modelscope.cn/models/Qwen/Qwen3-4B-GGUF');
      expect(result.downloadUrls, isEmpty);
      expect(result.modelName, 'Qwen3-4B-GGUF');
      expect(result.note, isNotNull);
    });

    test('empty input returns empty result', () {
      expect(ModelUrlParser.parse('').isEmpty, isTrue);
    });
  });

  group('QuantizationRecommender.recommend', () {
    test('recommends highest quality that fits budget', () {
      final variants = ['Q4_K_M', 'Q5_K_M', 'Q8_0'];
      // 8GB RAM → budget ~3.9GB → Q5_K_M (2900MB) fits, Q8_0 (4300MB) doesn't
      final rec = QuantizationRecommender.recommend(variants, ramMb: 8000);
      expect(rec, 'Q5_K_M');
    });

    test('returns null when nothing fits', () {
      final rec =
          QuantizationRecommender.recommend(['Q8_0'], ramMb: 2000);
      expect(rec, isNull);
    });
  });
}
