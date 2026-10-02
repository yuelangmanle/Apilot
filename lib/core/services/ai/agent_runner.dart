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

  /// 收集到的思考过程（工具模式之前完全不收集，用户就"看不到思考"）。
  final String thinking;

  const AgentResult({
    required this.text,
    this.steps = const [],
    this.error,
    this.thinking = '',
  });
}

/// 带工具的对话循环：本地模型与云端模型共用同一套机制。
///
/// 流程：模型输出 `@@TOOL {...}` → 执行 → 结果回灌 → 继续，直到模型给出
/// 自然语言回答（或达到步数上限）。工具说明由 [ToolRegistry] 注入系统提示词。
class AgentRunner {
  AgentRunner._();

  static const int maxSteps = 6;

  /// 云端模型 + 本地模型统一入口。
  ///
  /// 路由规则（**看当前对话本身，不看全局 AI 设置**）：
  /// - 传了 [localEngine] 且已加载 → 一律走本地推理（本地对话页）；
  /// - 否则用 [cloudConfig]（云端对话页自己的配置）→ 再退到 AiService 的全局来源。
  /// 之前的实现依赖"AI 设置里选的是本地/云端"，在本地对话里会导致
  /// "AI 未配置、调用失败或没有返回内容"——用户明明正在跟本地模型聊天。
  static Future<AgentResult> run({
    required String userPrompt,
    required List<ApiConfig> configs,
    ApiConfig? cloudConfig,
    LocalLlmEngine? localEngine,
    List<ChatTurn> history = const [],
    String? extraSystemPrompt,
    int maxTokens = 0,
    double? temp,
    double? topP,
    bool thinkingEnabled = false,
    void Function(AgentStep step)? onStep,
    /// 流式增量回调：工具模式也能边生成边显示（不再"全想完才吐字"）。
    void Function(String delta)? onDelta,
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

    // 动态预算：写 HTML/长文给大预算，普通问答给小预算（快且省）。
    final effectiveMaxTokens =
        maxTokens > 0 ? maxTokens : budgetFor(userPrompt);
    final steps = <AgentStep>[];
    final thinkingBuffer = StringBuffer();
    var prompt = userPrompt;
    // 截屏工具产出的图片：下一轮作为图片附件回灌（多模态模型才能"看"）。
    final pendingImages = <String>[];

    for (var step = 0; step < maxSteps; step++) {
      final reply = await _ask(
        systemPrompt: systemPrompt,
        userPrompt: prompt,
        history: history,
        configs: configs,
        cloudConfig: cloudConfig,
        localEngine: localEngine,
        maxTokens: effectiveMaxTokens,
        imagePaths: List<String>.from(pendingImages),
        onDelta: onDelta,
        // 只有云端对话（传了 cloudConfig）才走云端流式；
        // 本地对话必须走本地引擎，否则开插件后会去问全局 AI 设置
        // （表现为「AI 未配置」或偷偷花用户的云端额度）。
        allowCloudStreaming: cloudConfig != null,
      );
      pendingImages.clear();
      final answer = reply.text;
      if (reply.thinking.isNotEmpty) thinkingBuffer.write(reply.thinking);
      if (answer == null || answer.trim().isEmpty) {
        return AgentResult(
          text: steps.isEmpty ? '' : _summarizeSteps(steps),
          steps: steps,
          error: 'AI 未配置、调用失败或没有返回内容',
          thinking: thinkingBuffer.toString(),
        );
      }
      final call = ToolRegistry.parseCall(answer);
      if (call == null) {
        return AgentResult(
          text: ToolRegistry.stripCall(answer),
          steps: steps,
          thinking: thinkingBuffer.toString(),
        );
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
    final wrapUp = await _ask(
      systemPrompt: systemPrompt,
      userPrompt: '请直接总结已有信息回答用户，不要再调用工具。'
          '用户问题：$userPrompt\n\n已获得的信息：\n${_summarizeSteps(steps)}',
      history: history,
      configs: configs,
      cloudConfig: cloudConfig,
      localEngine: localEngine,
      maxTokens: effectiveMaxTokens,
      temp: temp,
      topP: topP,
      thinkingEnabled: thinkingEnabled,
    );
    if (wrapUp.thinking.isNotEmpty) thinkingBuffer.write(wrapUp.thinking);
    return AgentResult(
      text: (wrapUp.text == null || wrapUp.text!.isEmpty)
          ? _summarizeSteps(steps)
          : wrapUp.text!,
      steps: steps,
      thinking: thinkingBuffer.toString(),
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
  /// 按任务类型给生成预算：长产出（网页/代码/文章）给大预算，否则小预算。
  /// 用户反馈的"写 HTML 最后报没有返回内容"就是固定预算被截断导致的。
  static int budgetFor(String prompt) {
    final lower = prompt.toLowerCase();
    final isLongForm = lower.contains('html') ||
        lower.contains('网页') ||
        lower.contains('页面') ||
        lower.contains('代码') ||
        lower.contains('脚本') ||
        lower.contains('写一篇') ||
        lower.contains('文章') ||
        lower.contains('摘要长') ||
        lower.contains('完整');
    if (isLongForm) return 4096;
    if (prompt.length > 200) return 2048;
    return 1024;
  }

  /// 判断输出是否明显被截断（写代码/HTML 时标签不闭合、或以未完成符号结尾）。
  static bool looksTruncated(String text, String prompt) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    final lower = prompt.toLowerCase();
    final isCode = lower.contains('html') ||
        lower.contains('网页') ||
        lower.contains('页面') ||
        trimmed.contains('```') ||
        trimmed.contains('<!DOCTYPE') ||
        trimmed.contains('<html');
    if (!isCode) return false;
    if (trimmed.endsWith('```')) return false; // 正常收尾
    if (trimmed.contains('</html>')) return false;
    // 以半个标记/悬空连接符结尾 → 判定截断。
    return trimmed.endsWith('<') ||
        trimmed.endsWith('</') ||
        trimmed.endsWith('-') ||
        trimmed.endsWith(',') ||
        trimmed.endsWith('、') ||
        (trimmed.contains('<html') && !trimmed.contains('</html>'));
  }

  static Future<({String? text, String thinking})> _ask({
    required String systemPrompt,
    required String userPrompt,
    required List<ChatTurn> history,
    required List<ApiConfig> configs,
    ApiConfig? cloudConfig,
    LocalLlmEngine? localEngine,
    required int maxTokens,
    List<String> imagePaths = const [],
    void Function(String delta)? onDelta,
    bool allowCloudStreaming = false,
    double? temp,
    double? topP,
    bool thinkingEnabled = false,
  }) async {
    // 路由规则（严格）：
    // · 云端对话页传了 cloudConfig → 一律走那个云端配置（绝不被本地引擎劫持）；
    // · 本地对话页传了引擎 → 用本地；
    // · 两者都没有（AI 诊断等功能）→ 按全局"AI 设置"选来源。
    var engine = localEngine;
    if (allowCloudStreaming && cloudConfig != null) {
      // 云端对话：直接流式调用，不再经过本地引擎判定。
      final cloud = await AiService.ask(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        configs: configs,
        preferredConfig: cloudConfig,
        maxTokens: maxTokens,
        onDelta: onDelta,
      );
      return (text: cloud, thinking: '');
    }
    if (cloudConfig == null && (engine == null || !engine.isLoaded)) {
      final shared = AiService.sharedLocalEngine;
      if (shared != null && await AiService.isLocalSourceSelected()) {
        engine = shared;
      }
    }
    final useLocal = engine != null && engine.isLoaded;
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
        // 用流式收集：正文与思考都拿到（工具模式也要能看到思考过程）。
        final content = StringBuffer();
        final thinking = StringBuffer();
        await for (final chunk in engine
            .generateStream(
              messages,
              maxTokens: maxTokens,
              temp: temp ?? 0.6,
              topP: topP ?? 0.9,
              // 会话里的"深度思考"开关在工具模式下也要生效。
              thinkingEnabled: thinkingEnabled,
            )
            .timeout(const Duration(minutes: 4))) {
          if (chunk.content != null) {
            content.write(chunk.content);
            onDelta?.call(chunk.content!);
          }
          if (chunk.thinking != null) thinking.write(chunk.thinking);
        }
        return (text: content.toString(), thinking: thinking.toString());
      } catch (e) {
        debugPrint('[Agent] 本地推理失败: $e');
        return (text: null, thinking: '');
      }
    }
    final cloud = await AiService.ask(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      configs: configs,
      // 云端对话页把自己的配置传进来：不再依赖全局"AI 设置"选没选。
      preferredConfig: cloudConfig,
      maxTokens: maxTokens,
    );
    return (text: cloud, thinking: '');
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
