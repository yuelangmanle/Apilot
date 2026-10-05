import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import '../../models/api_config.dart';
import '../api_service.dart';
import '../local_llm/chat_conversation_store.dart';
import '../local_llm/local_llm_engine.dart';
import '../screenshot_storage.dart';
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
    List<ChatAttachment> attachments = const [],
    int maxTokens = 0,
    double? temp,
    double? topP,
    bool thinkingEnabled = false,
    int? maxToolSteps,
    void Function(AgentStep step)? onStep,

    /// 流式增量回调：工具模式也能边生成边显示（不再"全想完才吐字"）。
    void Function(String delta)? onDelta,
    ApiRequestCancellation? cancellation,
  }) async {
    ToolHost.visionEnabled = localEngine?.supportsVision ?? false;
    final toolDocs = ToolRegistry.describeForPrompt(
      task: userPrompt,
      compact: localEngine != null,
    );
    if (toolDocs.isEmpty) {
      return const AgentResult(text: '', error: '没有可用工具');
    }
    // 动态预算：写 HTML/长文给大预算，普通问答给小预算（快且省）。
    final effectiveMaxTokens =
        maxTokens > 0 ? maxTokens : budgetFor(userPrompt);
    final steps = <AgentStep>[];
    final thinkingBuffer = StringBuffer();
    var prompt = userPrompt;
    // 截屏工具产出的图片：下一轮作为图片附件回灌（多模态模型才能"看"）。
    final pendingImages = <String>[];
    String buildSystemPrompt() {
      final hasImageInput =
          attachments.any((a) => a.type == 'image') || pendingImages.isNotEmpty;
      return [
        '你是一个会使用工具的助手。回答要简洁，直接给结论。',
        if (cloudConfig != null)
          hasImageInput
              ? '本次请求已包含真实图片附件。不要仅依据模型名称、旧上下文或训练记忆声称自己是纯文本模型；'
                  '如果服务端明确拒绝图片输入，再如实说明无法分析。'
              : '本次请求没有图片附件，不要声称看过未收到的图片；是否支持视觉由服务端实际能力决定。',
        if (localEngine != null)
          '当前本地模型视觉输入状态：${localEngine.supportsVision ? '已启用' : '未启用'}。'
              '只有收到图片附件且视觉输入已启用时，才可描述画面内容。',
        if (extraSystemPrompt != null && extraSystemPrompt.isNotEmpty)
          extraSystemPrompt,
        toolDocs,
      ].join('\n\n');
    }

    ToolRegistry.lastScreenshotPath = null;
    ToolHost.screenshotLocation = null;

    final stepLimit = maxToolSteps ?? (localEngine != null ? 3 : maxSteps);
    for (var step = 0; step < stepLimit; step++) {
      final requestImages = List<String>.from(pendingImages);
      final requestAttachments =
          step == 0 ? attachments : const <ChatAttachment>[];
      late final _AgentReply reply;
      try {
        reply = await _ask(
          systemPrompt: buildSystemPrompt(),
          userPrompt: prompt,
          history: history,
          configs: configs,
          cloudConfig: cloudConfig,
          localEngine: localEngine,
          maxTokens: effectiveMaxTokens,
          imagePaths: requestImages,
          attachments: requestAttachments,
          onDelta: onDelta,
          allowCloudStreaming: cloudConfig != null,
          cancellation: cancellation,
        );
      } finally {
        await _deleteTemporaryScreenshots(requestImages);
      }
      pendingImages.clear();
      final answer = reply.text;
      if (reply.thinking.isNotEmpty) thinkingBuffer.write(reply.thinking);
      if (cancellation?.isCancelled == true) {
        return AgentResult(
          text: answer ?? '',
          steps: steps,
          thinking: thinkingBuffer.toString(),
        );
      }
      if (reply.error != null) {
        return AgentResult(
          text: steps.isEmpty ? '' : _summarizeSteps(steps),
          steps: steps,
          error: reply.error,
          thinking: thinkingBuffer.toString(),
        );
      }
      if (answer == null || answer.trim().isEmpty) {
        return AgentResult(
          text: steps.isEmpty ? '' : _summarizeSteps(steps),
          steps: steps,
          error: AiService.lastError ?? 'AI 未配置、调用失败或没有返回内容',
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
      final execution =
          await ToolRegistry.executeDetailed(call.name, call.args);
      final result = execution.text;
      // 截屏 → 图片回灌（引擎支持看图时）。
      if (call.name == 'screenshot') {
        final path =
            execution.attachmentPath ?? ToolRegistry.lastScreenshotPath;
        final engineForVision = localEngine;
        if (engineForVision != null &&
            !engineForVision.supportsVision &&
            engineForVision.hasVisionCandidate) {
          await engineForVision.ensureVision();
          ToolHost.visionEnabled = engineForVision.supportsVision;
        }
        if (path != null &&
            (cloudConfig != null ||
                (engineForVision?.supportsVision ?? false))) {
          pendingImages.add(path);
        } else if (path != null) {
          await ScreenshotStorage.deleteTemporary(path);
          ToolRegistry.lastScreenshotPath = null;
        }
      }
      if (cancellation?.isCancelled == true) {
        await _deleteTemporaryScreenshots(pendingImages);
        return AgentResult(
          text: '',
          steps: steps,
          thinking: thinkingBuffer.toString(),
        );
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
    final wrapUpImages = List<String>.from(pendingImages);
    late final _AgentReply wrapUp;
    try {
      wrapUp = await _ask(
        systemPrompt: buildSystemPrompt(),
        userPrompt: '请直接总结已有信息回答用户，不要再调用工具。'
            '用户问题：$userPrompt\n\n已获得的信息：\n${_summarizeSteps(steps)}',
        history: history,
        configs: configs,
        cloudConfig: cloudConfig,
        localEngine: localEngine,
        maxTokens: effectiveMaxTokens,
        imagePaths: wrapUpImages,
        attachments: attachments,
        onDelta: onDelta,
        temp: temp,
        topP: topP,
        thinkingEnabled: thinkingEnabled,
        allowCloudStreaming: cloudConfig != null,
        cancellation: cancellation,
      );
    } finally {
      await _deleteTemporaryScreenshots(wrapUpImages);
    }
    if (wrapUp.thinking.isNotEmpty) thinkingBuffer.write(wrapUp.thinking);
    if (wrapUp.error != null) {
      return AgentResult(
        text: _summarizeSteps(steps),
        steps: steps,
        error: wrapUp.error,
        thinking: thinkingBuffer.toString(),
      );
    }
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

  static Future<void> _deleteTemporaryScreenshots(
    Iterable<String> paths,
  ) async {
    for (final path in paths) {
      await ScreenshotStorage.deleteTemporary(path);
    }
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

  static Future<_AgentReply> _ask({
    required String systemPrompt,
    required String userPrompt,
    required List<ChatTurn> history,
    required List<ApiConfig> configs,
    ApiConfig? cloudConfig,
    LocalLlmEngine? localEngine,
    required int maxTokens,
    List<String> imagePaths = const [],
    List<ChatAttachment> attachments = const [],
    void Function(String delta)? onDelta,
    bool allowCloudStreaming = false,
    double? temp,
    double? topP,
    bool thinkingEnabled = false,
    ApiRequestCancellation? cancellation,
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
        history: [
          for (final turn in history)
            {
              'role': turn.isUser ? 'user' : 'assistant',
              'content': turn.text,
            },
        ],
        attachments: [
          ...attachments,
          for (final path in imagePaths)
            ChatAttachment(
              name: path.split('/').last,
              type: 'image',
              path: path,
            ),
        ],
        onDelta: onDelta,
        cancellation: cancellation,
      );
      return _AgentReply(
        text: cloud,
        thinking: '',
        error: cloud == null ? AiService.lastError : null,
      );
    }
    if (cloudConfig == null && (engine == null || !engine.isLoaded)) {
      final shared = AiService.sharedLocalEngine;
      if (shared != null && await AiService.isLocalSourceSelected()) {
        engine = shared;
      }
    }
    final useLocal = engine != null && engine.isLoaded;
    if (useLocal) {
      final inputImages = [
        ...attachments.where((attachment) => attachment.type == 'image'),
        for (final path in imagePaths)
          ChatAttachment(name: path.split('/').last, type: 'image', path: path),
      ];
      if (inputImages.isNotEmpty && !engine.supportsVision) {
        return const _AgentReply(
          text: '当前本地模型尚未启用视觉投影，暂时无法分析图片。'
              '请先下载并配对该模型对应的 mmproj 文件，再重新发送。',
          thinking: '',
        );
      }
      final promptWithFiles = StringBuffer(userPrompt);
      for (final attachment
          in attachments.where((attachment) => attachment.type == 'text')) {
        final content = attachment.content ?? '';
        if (content.isNotEmpty) {
          promptWithFiles
            ..writeln()
            ..writeln('文件「${attachment.name}」内容：')
            ..writeln('```')
            ..writeln(content)
            ..writeln('```');
        }
      }
      if (cancellation?.isCancelled == true) {
        return const _AgentReply(text: '', thinking: '');
      }
      cancellation?.setCancelHandler(engine.cancelGeneration);
      final messages = <LlamaChatMessage>[
        LlamaChatMessage.fromText(
            role: LlamaChatRole.system, text: systemPrompt),
        for (final turn in history)
          LlamaChatMessage.fromText(
            role: turn.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
            text: turn.text,
          ),
        if (inputImages.isNotEmpty && engine.supportsVision)
          // 截屏回灌：文本 + 图片（引擎已启用视觉投影）。
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaTextContent(promptWithFiles.toString()),
              for (final image in inputImages)
                if (image.path != null) LlamaImageContent(path: image.path!),
            ],
          )
        else
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: promptWithFiles.toString(),
          ),
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
              suppressThinking: !thinkingEnabled,
            )
            .timeout(const Duration(minutes: 4))) {
          if (cancellation?.isCancelled == true) {
            engine.cancelGeneration();
            break;
          }
          if (chunk.content != null) {
            content.write(chunk.content);
            onDelta?.call(chunk.content!);
          }
          if (chunk.thinking != null) thinking.write(chunk.thinking);
        }
        return _AgentReply(
          text: content.toString(),
          thinking: thinking.toString(),
        );
      } catch (e) {
        debugPrint('[Agent] 本地推理失败: $e');
        final message = '本地模型调用失败：$e';
        AiService.lastError = message;
        return _AgentReply(text: null, thinking: '', error: message);
      }
    }
    final cloud = await AiService.ask(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      configs: configs,
      // 云端对话页把自己的配置传进来：不再依赖全局"AI 设置"选没选。
      preferredConfig: cloudConfig,
      maxTokens: maxTokens,
      onDelta: onDelta,
      cancellation: cancellation,
    );
    return _AgentReply(
      text: cloud,
      thinking: '',
      error: cloud == null ? AiService.lastError : null,
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

class _AgentReply {
  final String? text;
  final String thinking;
  final String? error;

  const _AgentReply({this.text, this.thinking = '', this.error});
}
