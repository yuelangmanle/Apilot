import 'package:api_manager/core/services/local_llm/model_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模型能力识别：决定"能不能发图片""有没有深度思考开关"。
void main() {
  group('isProjectorFile', () {
    test('识别 mmproj 视觉投影文件', () {
      expect(ModelCapabilities.isProjectorFile('mmproj-model-f16.gguf'), isTrue);
      expect(ModelCapabilities.isProjectorFile('MMProj-F32.gguf'), isTrue);
    });

    test('普通模型文件不算投影文件', () {
      expect(ModelCapabilities.isProjectorFile('Qwen3-1.7B-Q4_K_M.gguf'),
          isFalse);
      expect(ModelCapabilities.isProjectorFile('mmproj.json'), isFalse);
    });
  });

  group('isVisionFamily', () {
    test('多模态家族可识别（含路径形态）', () {
      expect(ModelCapabilities.isVisionFamily('gemma-3-4b-it-Q4_K_M.gguf'),
          isTrue);
      expect(
          ModelCapabilities.isVisionFamily(
              '/models/qwen2.5-vl-7b-instruct-q4_k_m.gguf'),
          isTrue);
      expect(ModelCapabilities.isVisionFamily('llava-v1.6-mistral-7b.gguf'),
          isTrue);
      expect(ModelCapabilities.isVisionFamily('minicpm-v-2_6.Q4_K_M.gguf'),
          isTrue);
    });

    test('纯文本模型不误判', () {
      expect(ModelCapabilities.isVisionFamily('Qwen3-1.7B-Q4_K_M.gguf'),
          isFalse);
      expect(ModelCapabilities.isVisionFamily('Llama-3.2-3B-Instruct-Q4_K_M.gguf'),
          isFalse);
      expect(ModelCapabilities.isVisionFamily('deepseek-r1-distill-qwen-7b.gguf'),
          isFalse);
    });

    test('下划线命名也能识别（normalize）', () {
      expect(ModelCapabilities.isVisionFamily('Qwen2_5_VL_7B.gguf'), isTrue);
    });
  });

  group('supportsThinking', () {
    test('推理模型识别', () {
      expect(ModelCapabilities.supportsThinking('Qwen3-4B-Q4_K_M.gguf'),
          isTrue);
      expect(
          ModelCapabilities.supportsThinking('DeepSeek-R1-Distill-Qwen-7B.gguf'),
          isTrue);
      expect(ModelCapabilities.supportsThinking('QwQ-32B-Q4_K_M.gguf'), isTrue);
      expect(ModelCapabilities.supportsThinking('GLM-4.5-Air-Q4_K_M.gguf'),
          isTrue);
    });

    test('普通模型不显示思考开关', () {
      expect(ModelCapabilities.supportsThinking('gemma-3-1b-it-Q4_K_M.gguf'),
          isFalse);
      expect(
          ModelCapabilities.supportsThinking('Llama-3.2-3B-Instruct-Q4_K_M.gguf'),
          isFalse);
    });
  });

  group('isShardedFile', () {
    test('分片文件识别（App 内不支持多文件合并）', () {
      expect(
          ModelCapabilities.isShardedFile('big-Q4_K_M-00001-of-00003.gguf'),
          isTrue);
      expect(ModelCapabilities.isShardedFile('normal-Q4_K_M.gguf'), isFalse);
    });
  });

  group('describe', () {
    test('文本模型 + 无思考', () {
      expect(
          ModelCapabilities.describe('llama-3.2-3b-q4_k_m.gguf'),
          '纯文本 · 无深度思考');
    });

    test('多模态家族但未加载投影时注明前提', () {
      final text = ModelCapabilities.describe('gemma-3-1b-it-Q4_K_M.gguf');
      expect(text, contains('需视觉投影文件'));
    });

    test('已加载投影的多模态模型', () {
      expect(
          ModelCapabilities.describe('gemma-3-1b-it-Q4_K_M.gguf',
              visionLoaded: true),
          '多模态（可看图） · 无深度思考');
    });
  });
}
