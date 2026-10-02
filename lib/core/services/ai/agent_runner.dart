import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../../models/api_config.dart';
import '../local_llm/local_llm_engine.dart';
import 'ai_service.dart';
import 'tool_registry.dart';

/// 一次工具调用记录（界面展示用）。
class AgentStep {
  final String tool;
  final Map<String, dynamic> args;
  final String result;

  const AgentStep({
    required this.tool,
    required this.args,
    required this.result,
  });

  String get argsLabel => args.entries
      .map((e) => '${e.key}=${e.value}')
      .join(', ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Agent 运行结果。
class AgentResult {
  final String text;
  final List<AgentStep> steps;
  final String? error;

  const AgentResult({required this.text, this.steps = const [], this.error});
}

/// 带工具的对话循环：本地模型与云端模型共用同一套机制。
///
/// 流程：模型输出 `@@TOOL {...}` → 执行 → 结果回灌 → 继续，直到模型给出
/// 自然语言回答（或达到步数上限）。工具说明由 [ToolRegistry] 注入系统提示词。
class AgentRunner {
  AgentRunner._();

  static const int maxSteps = 6;

  /// 云端模型 + 本地模型统一入口：[localEngine] 非空且已加载时走本地推理。
  static Future<AgentResult> run({
    required String userPrompt,
    required List<ApiConfig> configs,
    LocalLlmEngine? localEngine,
    List<ChatTurn> history = const [],
    String? extraSystemPrompt,
    int maxTokens = 900,
    void Function(AgentStep step)? onStep,
  }) async {
    final toolDocs = ToolRegistry.describeForPrompt();
    if (toolDocs.isEmpty) {
      return const AgentResult(text: '', error: '没有可用工具');
    }
    final systemPrompt = [
      '你是一个会使用工具的助手。回答要简洁，直接给结论。',
      if (extraSystemPrompt != null && extraSystemPrompt.isNotEmpty)
        extraSystemPrompt,
      toolDocs,
    ].join('\n\n');

    final steps = <AgentStep>[];
    var prompt = userPrompt;
    // 截屏工具产出的图片：下一轮作为图片附件回灌（多模态模型才能"看"）。
    final pendingImages = <String>[];

    for (var step = 0; step < maxSteps; step++) {
      final answer = await _ask(
        systemPrompt: systemPrompt,
        userPrompt: prompt,
        history: history,
        configs: configs,
        localEngine: localEngine,
        maxTokens: maxTokens,
        imagePaths: List<String>.from(pendingImages),
      );
      pendingImages.clear();
      if (answer == null || answer.trim().isEmpty) {
        return AgentResult(
          text: steps.isEmpty ? '' : _summarizeSteps(steps),
          steps: steps,
          error: 'AI 未配置、调用失败或没有返回内容',
        );
      }
      final call = ToolRegistry.parseCall(answer);
      if (call == null) {
        return AgentResult(text: ToolRegistry.stripCall(answer), steps: steps);
      }
      final result = await ToolRegistry.execute(call.name, call.args);
      // 截屏 → 图片回灌（引擎支持看图时）。
      if (call.name == 'screenshot') {
        final path = ToolRegistry.lastScreenshotPath;
        final engineForVision = localEngine ?? AiService.sharedLocalEngine;
        if (path != null && (engineForVision?.supportsVision ?? false)) {
          pendingImages.add(path);
        }
      }
      final recorded = AgentStep(
        tool: call.name,
        args: call.args,
        result: result,
      );
      steps.add(recorded);
      onStep?.call(recorded);
      prompt = '工具 ${call.name} 的执行结果如下：\n$result\n\n'
          '请基于这个结果完成用户最初的请求：$userPrompt';
    }

    // 步数用尽：把已有的工具结果整理成回答。
    final answer = await _ask(
      systemPrompt: systemPrompt,
      userPrompt: '请直接总结已有信息回答用户，不要再调用工具。'
          '用户问题：$userPrompt\n\n已获得的信息：\n${_summarizeSteps(steps)}',
      history: history,
      configs: configs,
      localEngine: localEngine,
      maxTokens: maxTokens,
    );
    return AgentResult(
      text: answer ?? _summarizeSteps(steps),
      steps: steps,
    );
  }

  static String _summarizeSteps(List<AgentStep> steps) {
    final buffer = StringBuffer();
    for (final step in steps) {
      buffer.writeln('【${step.tool}】${step.argsLabel}');
      buffer.writeln(step.result);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// 单次问答：优先本地引擎，否则走 AiService（云端）。
  static Future<String?> _ask({
    required String systemPrompt,
    required String userPrompt,
    required List<ChatTurn> history,
    required List<ApiConfig> configs,
    LocalLlmEngine? localEngine,
    required int maxTokens,
    List<String> imagePaths = const [],
  }) async {
    final engine = localEngine ?? AiService.sharedLocalEngine;
    final useLocal = engine != null &&
        engine.isLoaded &&
        await AiService.isLocalSourceSelected();
    if (useLocal) {
      final messages = <LlamaChatMessage>[
        LlamaChatMessage.fromText(
            role: LlamaChatRole.system, text: systemPrompt),
        for (final turn in history)
          LlamaChatMessage.fromText(
            role: turn.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
            text: turn.text,
          ),
        if (imagePaths.isNotEmpty && engine.supportsVision)
          // 截屏回灌：文本 + 图片（引擎已启用视觉投影）。
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaTextContent(userPrompt),
              for (final path in imagePaths) LlamaImageContent(path: path),
            ],
          )
        else
          LlamaChatMessage.fromText(
              role: LlamaChatRole.user, text: userPrompt),
      ];
      try {
        return await engine
            .generate(messages, maxTokens: maxTokens, temp: 0.6)
            .timeout(const Duration(minutes: 3));
      } catch (e) {
        debugPrint('[Agent] 本地推理失败: $e');
        return null;
      }
    }
    return AiService.ask(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      configs: configs,
      maxTokens: maxTokens,
    );
  }

  /// 供测试：解析 + 执行的纯函数部分。
  @visibleForTesting
  static Map<String, dynamic>? parseToolCallForTest(String text) {
    final call = ToolRegistry.parseCall(text);
    if (call == null) return null;
    return {'name': call.name, 'args': call.args};
  }

  /// 供测试：把工具结果序列化成可读文本。
  @visibleForTesting
  static String summarizeForTest(List<AgentStep> steps) =>
      _summarizeSteps(steps);

  @visibleForTesting
  static String encodeArgsForTest(Map<String, dynamic> args) =>
      jsonEncode(args);
}

/// 对话历史里的一轮（供 Agent 带上上下文）。
class ChatTurn {
  final bool isUser;
  final String text;

  const ChatTurn({required this.isUser, required this.text});
}
