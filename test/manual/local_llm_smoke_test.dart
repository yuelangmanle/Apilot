import 'dart:io';

import 'package:api_manager/core/services/local_llm/local_llm_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

/// 本地推理端到端冒烟测试（真实 GGUF，手动运行）：
///
///   MODEL_PATH=/path/to/model.gguf flutter test test/manual/local_llm_smoke_test.dart
///
/// 覆盖用户报告的"下载的模型对话没有回复"场景：走的就是聊天页用的
/// [LocalLlmEngine.loadModel] + [LocalLlmEngine.generateStream] 同一条路径。
/// 没有设置 MODEL_PATH 时整组跳过（CI 不跑，避免下载大文件）。
void main() {
  final modelPath = Platform.environment['MODEL_PATH'];
  final hasModel = modelPath != null &&
      modelPath.isNotEmpty &&
      File(modelPath).existsSync();

  group('本地推理端到端', () {
    test('加载模型 → 流式生成 → 拿到非空回复', () async {
      if (!hasModel) {
        // ignore: avoid_print
        print('跳过：未设置 MODEL_PATH（本机无模型时 CI 不跑）');
        return;
      }
      final engine = LocalLlmEngine();
      await engine.loadModel(modelPath);
      expect(engine.isLoaded, isTrue);
      // 纯文本模型不应启用视觉（不匹配的投影绝不自动挂载）。
      expect(engine.supportsVision, isFalse,
          reason: '纯文本模型不应有视觉能力');

      final messages = <LlamaChatMessage>[
        const LlamaChatMessage.fromText(
            role: LlamaChatRole.user, text: 'Say hi in one short word.'),
      ];
      // ignore: prefer_const_literals_to_create_immutables

      final buffer = StringBuffer();
      var frames = 0;
      await for (final chunk in engine.generateStream(
        messages,
        maxTokens: 24,
        temp: 0.7,
      )) {
        frames++;
        if (chunk.content != null) buffer.write(chunk.content);
      }

      // ignore: avoid_print
      print('生成 $frames 帧，输出："${buffer.toString().trim()}"');
      expect(frames, greaterThan(0), reason: '必须有增量帧产出');
      expect(buffer.toString().trim(), isNotEmpty,
          reason: '必须有实际文本回复（用户报告的"没有回复"就是这里为空）');
      await engine.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('多轮对话（带历史）也能出结果', () async {
      if (!hasModel) return;
      final engine = LocalLlmEngine();
      await engine.loadModel(modelPath, contextSize: 2048);
      final messages = <LlamaChatMessage>[
        const LlamaChatMessage.fromText(
            role: LlamaChatRole.user, text: 'My name is Li.'),
        const LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant, text: 'Nice to meet you, Li.'),
        const LlamaChatMessage.fromText(
            role: LlamaChatRole.user, text: 'What is my name?'),
      ];
      final buffer = StringBuffer();
      await for (final chunk
          in engine.generateStream(messages, maxTokens: 32, temp: 0.5)) {
        if (chunk.content != null) buffer.write(chunk.content);
      }
      // ignore: avoid_print
      print('多轮输出："${buffer.toString().trim()}"');
      expect(buffer.toString().trim(), isNotEmpty);
      await engine.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
