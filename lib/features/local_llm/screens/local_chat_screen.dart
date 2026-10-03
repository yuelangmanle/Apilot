import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';
import 'package:uuid/uuid.dart';

import 'package:provider/provider.dart';
import '../../../core/services/ai/agent_runner.dart' as agent;
import '../../../core/services/ai/ai_service.dart';
import '../../../core/services/ai/memory_store.dart';
import '../../../core/services/ai/tool_registry.dart';
import '../../../core/services/api_service.dart';
import '../../api_management/providers/api_provider.dart';
import '../../../core/services/local_llm/chat_conversation_store.dart';
import '../../../core/services/local_llm/local_llm_tuning.dart';
import '../../../core/services/local_llm/model_capabilities.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../core/services/local_llm/model_storage_settings.dart';
import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../shared/theme/color_scheme.dart';
import '../widgets/chat_code_block.dart';
import '../widgets/tool_panel.dart';
import 'conversation_list_screen.dart';

/// 本地对话：多轮对话 + 参数调节 + 思考过程折叠 + 附件 + 持久化。
class LocalChatScreen extends StatefulWidget {
  final String modelPath;
  final String modelName;

  /// 打开已有对话时传入 id；为空则新建对话。
  final String? conversationId;

  const LocalChatScreen({
    super.key,
    required this.modelPath,
    required this.modelName,
    this.conversationId,
  });

  @override
  State<LocalChatScreen> createState() => _LocalChatScreenState();
}

class _LocalChatScreenState extends State<LocalChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _store = ChatConversationStore();
  final _pendingAttachments = <ChatAttachment>[];

  late final LocalLlmEngine _engine;
  bool _ownsEngine = false;
  late ChatConversation _conversation;

  bool _isGenerating = false;
  bool _modelReady = false;
  bool _stopRequested = false;
  bool _enablingVision = false;
  bool _switchingModel = false;
  bool _toolsEnabled = ToolRegistry.masterEnabled;
  bool _compressing = false;
  String? _memorySectionCache;
  String? _loadError;
  // ignore: prefer_final_fields
  int _contextSize = 4096;
  final List<agent.AgentStep> _pendingSteps = [];
  final ValueNotifier<int> _streamRevision = ValueNotifier(0);
  String _streamText = '';
  String _streamThinking = '';
  final Set<int> _expandedThinking = {};
  bool _scrollScheduled = false;
  ApiRequestCancellation? _requestCancellation;

  @override
  void initState() {
    super.initState();
    final registered = AiService.registeredLocalEngine;
    if (registered != null && !registered.isDisposed) {
      // 页面之间复用同一个 native 引擎，避免每次打开对话都重新加载 GGUF，
      // 也避免两个模型同时编译 Vulkan 导致手机卡死或 native 崩溃。
      _engine = registered;
    } else {
      _engine = LocalLlmEngine();
      _ownsEngine = true;
    }
    _init();
  }

  Future<void> _init() async {
    // 载入已有对话，或新建一个。
    ChatConversation? loaded;
    if (widget.conversationId != null) {
      loaded = await _store.load(widget.conversationId!);
    }
    _conversation = loaded ??
        ChatConversation(
          id: const Uuid().v4(),
          title: widget.modelName,
          modelPath: widget.modelPath,
          modelName: widget.modelName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: [],
        );
    // 加载模型（复用已加载的引擎则跳过）。
    if (!_engine.isLoaded || _engine.loadedModelPath != widget.modelPath) {
      try {
        await _engine.loadModel(widget.modelPath, contextSize: _contextSize);
      } catch (e) {
        // 之前只弹一句 SnackBar，页面永远停在转圈（大模型加载几十秒~几分钟，
        // 失败了也没有出路）。现在记录错误，渲染错误页 + 重试按钮。
        if (mounted) {
          setState(() => _loadError = '$e');
        }
        return;
      }
    }
    if (mounted) {
      // 注册为共享引擎：AI 诊断/分析等其他 AI 功能直接复用，无需重复加载。
      AiService.registerLocalEngine(_engine);
      // 截屏工具是否"能被看见"取决于当前模型有没有视觉能力。
      ToolHost.visionEnabled = _engine.supportsVision;
      setState(() => _modelReady = true);
      _scrollToBottom();
    }
  }

  Future<void> _send() async {
    // 在第一个 await 之前取出依赖（避免 async gap 里用 context）。
    final configs = context.read<ApiProvider>().allApiConfigs;
    var text = _controller.text.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _isGenerating) return;

    debugPrint(
        '[CHAT-DIAG] send: text="${text.length > 20 ? '${text.substring(0, 20)}…' : text}" '
        'attachments=${_pendingAttachments.length} tools=$_toolsEnabled '
        'engineLoaded=${_engine.isLoaded}');
    // 关键守卫：引擎里装的未必是本会话的模型（可能是上一个模型、或还在
    // 加载中）。此前直接把生成流挂起，用户面对 90+ 秒的"…"以为死机，
    // 反复退出重进又触发并发加载 → 闪退。现在：加载中提示等待；
    // 装的是别的模型就现场切换（横幅反馈），加载完再继续发送。
    if (_engine.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('模型正在加载，请等加载完成后再发送'), duration: Duration(seconds: 2)));
      return;
    }
    if (!_engine.isReadyFor(widget.modelPath, contextSize: _contextSize)) {
      setState(() => _switchingModel = true);
      try {
        await _engine.loadModel(widget.modelPath, contextSize: _contextSize);
        if (mounted) {
          AiService.registerLocalEngine(_engine);
          ToolHost.visionEnabled = _engine.supportsVision;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('模型加载失败：$e'), backgroundColor: AppColors.error));
        }
        return;
      } finally {
        if (mounted) setState(() => _switchingModel = false);
      }
    }
    // 图片处理：模型能看图就直接发；有投影候选就先按需启用；
    // 都没有则讲清楚让用户决定，绝不让引擎抛错（用户看不懂）。
    final hasImage = _pendingAttachments.any((a) => a.type == 'image');
    if (hasImage && !_engine.supportsVision) {
      var enabled = false;
      if (_engine.hasVisionCandidate) {
        setState(() => _enablingVision = true);
        enabled = await _engine.ensureVision();
        if (mounted) setState(() => _enablingVision = false);
        if (enabled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('视觉投影已启用，现在可以看图了'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2)));
        }
      }
      if (!enabled) {
        final action = await _confirmTextOnly();
        if (action == 'bind') {
          final bound = await _bindProjector();
          if (bound && mounted) {
            setState(() =>
                _pendingAttachments.removeWhere((a) => a.type == 'image'));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('已绑定视觉投影，请重新发送图片'),
                backgroundColor: AppColors.success));
          }
          return;
        }
        if (action != 'text') return;
        setState(
            () => _pendingAttachments.removeWhere((a) => a.type == 'image'));
        text = _controller.text.trim();
        if (text.isEmpty && _pendingAttachments.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('图片已移除，请输入文字后再发送')));
          }
          return;
        }
      }
    }

    // 上下文管理（分层，对齐业界共识）：
    // ① 70% 先做免费折叠；② 85%（或用户阈值）才调模型做增量摘要。
    if (_needsPrune) _pruneOldContent();
    if (_needsSummarize) {
      await _compressContext(silent: true);
    }

    // 长期记忆：① 用户明确说"记住…"就自动入库；
    // ② 开了记忆插件时，把相关记忆注入系统提示词。
    if (ToolRegistry.isCategoryEnabled('memory')) {
      final explicit = MemoryStore.extractExplicitMemory(text);
      if (explicit != null) {
        await MemoryStore.save(explicit);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已记住：$explicit（可在「记忆」里查看/删除）'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '查看',
              onPressed: () => showToolPanel(
                context,
                toolsEnabled: _toolsEnabled,
                onToolsChanged: (v) => setState(() => _toolsEnabled = v),
                visionAvailable: _engine.supportsVision,
              ),
            ),
          ));
        }
      }
    }

    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    final cancellation = ApiRequestCancellation();
    cancellation.setCancelHandler(_engine.cancelGeneration);
    _requestCancellation = cancellation;
    _controller.clear();
    setState(() {
      _conversation.messages.add(ChatMessageRecord(
        role: 'user',
        text: text,
        attachments: attachments,
      ));
      _pendingAttachments.clear();
      _isGenerating = true;
      _stopRequested = false;
      _streamText = '';
      _streamThinking = '';
    });
    _scrollToBottom();

    // 工具模式：走 Agent 循环（搜索/抓网页/算术/存 HTML/查 App）。
    // 关键：把增量回调接到界面上——边生成边显示，不再"全想完才吐字"。
    if (_toolsEnabled) {
      _pendingSteps.clear();
      final stopwatch = Stopwatch()..start();
      var firstTokenMs = -1;
      final streamed = StringBuffer();
      var isToolProtocol = false;
      var protocolTail = '';
      DateTime? lastToolUiUpdate;
      final history = <agent.ChatTurn>[
        for (final record in _conversation.messages
            .where((m) => m.role == 'user' || m.role == 'assistant')
            .toList()
            .take(_conversation.messages.length - 1))
          agent.ChatTurn(isUser: record.role == 'user', text: record.text),
      ];
      try {
        final result = await agent.AgentRunner.run(
          userPrompt: text,
          configs: configs,
          // 本地对话一律走本地引擎（不再看全局 AI 来源设置）。
          localEngine: _engine,
          temp: _conversation.settings.temp,
          topP: _conversation.settings.topP,
          thinkingEnabled: _conversation.settings.thinkingEnabled &&
              ModelCapabilities.supportsThinking(widget.modelName),
          // 传**完整历史**（不再取"最后 6 条"）：滑动窗口会让每轮提示词前缀
          // 都发生变化，llama.cpp 的前缀缓存（KV 复用）就完全失效——每轮都要
          // 从头 prefill。历史过长时由上下文管理（折叠/摘要）负责收敛。
          history: history,
          // 增量回调：边生成边显示（工具协议文本不显示给用户）。
          onDelta: (delta) {
            if (!mounted) return;
            if (firstTokenMs < 0) firstTokenMs = stopwatch.elapsedMilliseconds;
            streamed.write(delta);
            final protocolWindow = '$protocolTail$delta';
            if (!isToolProtocol && protocolWindow.contains('@@')) {
              isToolProtocol = true;
            }
            protocolTail = protocolWindow.length > 5
                ? protocolWindow.substring(protocolWindow.length - 5)
                : protocolWindow;
            final now = DateTime.now();
            final shouldUpdate = lastToolUiUpdate == null ||
                now.difference(lastToolUiUpdate!) >=
                    const Duration(milliseconds: 80);
            if (!isToolProtocol && shouldUpdate) {
              lastToolUiUpdate = now;
              _streamText = streamed.toString();
              _streamRevision.value++;
              _scrollToBottom(animate: false);
            }
          },
          onStep: (step) {
            if (mounted) {
              setState(() {
                _pendingSteps.add(step);
                // 工具开始执行后清掉流式草稿（那是协议文本）。
                _streamText = '';
              });
            }
          },
          cancellation: cancellation,
        );
        stopwatch.stop();
        if (mounted) {
          final stopped = _stopRequested || cancellation.isCancelled;
          // 截断兜底：写代码/HTML 以未闭合结尾时自动续写一次。
          var finalText = result.text;
          var continueCount = 0;
          while (!stopped &&
              continueCount < 2 &&
              agent.AgentRunner.looksTruncated(finalText, text)) {
            continueCount++;
            final more = await _engine.generate([
              const LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: '继续输出，从断掉的地方接着写，不要重复已输出的内容、'
                      '不要解释，直接接着写：'),
            ], maxTokens: 3072, temp: 0.4);
            if (more.trim().isEmpty) break;
            finalText = '$finalText$more';
          }
          final speed = _formatSpeed(
            chars: finalText.length,
            firstTokenMs: firstTokenMs,
            totalMs: stopwatch.elapsedMilliseconds,
          );
          setState(() {
            _streamText = '';
            _conversation.messages.add(ChatMessageRecord(
              role: 'assistant',
              text: finalText.isEmpty
                  ? (stopped
                      ? '（已停止生成）'
                      : '${result.error ?? '（没有返回内容）'}'
                          '${AiService.lastError == null ? '' : '\n原因：${AiService.lastError}'}')
                  : (stopped ? '$finalText（已停止）' : finalText),
              // 工具模式也把思考过程留下来（之前完全不收集，所以"看不到思考"）。
              thinking: result.thinking.isEmpty ? null : result.thinking,
              speed: speed,
              toolSteps: [
                for (final step in result.steps)
                  '${step.tool}(${step.argsLabel})：${_shorten(step.result)}',
              ],
            ));
            _isGenerating = false;
            _stopRequested = false;
          });
          await _store.save(_conversation);
        }
      } catch (e, st) {
        debugPrint('[CHAT-DIAG] tool send threw: $e\n$st');
        if (mounted) {
          final stopped = _stopRequested || cancellation.isCancelled;
          setState(() {
            _isGenerating = false;
            _conversation.messages.add(ChatMessageRecord(
              role: 'assistant',
              text: stopped ? '（已停止生成）' : '工具调用失败：$e',
            ));
            _stopRequested = false;
          });
          await _store.save(_conversation);
        }
      } finally {
        if (identical(_requestCancellation, cancellation)) {
          _requestCancellation = null;
        }
      }
      _scrollToBottom();
      return;
    }

    final plainStopwatch = Stopwatch()..start();
    var plainFirstTokenMs = -1;
    try {
      // 记忆注入：**每个会话只算一次**并缓存。
      // 之前每轮都按当前输入重新检索并拼进 system 提示词 → system 段每轮变化，
      // 前缀缓存（KV 复用）全部失效，每轮都要全量重新 prefill（明显变慢）。
      if (ToolRegistry.isCategoryEnabled('memory') &&
          _memorySectionCache == null) {
        _memorySectionCache = await MemoryStore.buildPromptSection(text);
      }
      final memorySection = _memorySectionCache ?? '';
      final messages = _buildEngineMessages(memorySection: memorySection);
      debugPrint('[CHAT-DIAG] messages=${messages.length} roles='
          '${messages.map((m) => m.role).toList()}');
      final buffer = StringBuffer();
      final thinking = StringBuffer();
      var chunkCount = 0;
      DateTime? lastPlainUiUpdate;

      await for (final chunk in _engine.generateStream(
        messages,
        maxTokens: _conversation.settings.maxTokens,
        temp: _conversation.settings.temp,
        topP: _conversation.settings.topP,
        thinkingEnabled: _conversation.settings.thinkingEnabled &&
            ModelCapabilities.supportsThinking(widget.modelName),
        // 只对认得该指令的家族生效（引擎内部还会再判一次）。
        suppressThinking: !_conversation.settings.thinkingEnabled,
      )) {
        if (!mounted) return;
        if (_stopRequested || cancellation.isCancelled) break;
        if (plainFirstTokenMs < 0) {
          plainFirstTokenMs = plainStopwatch.elapsedMilliseconds;
        }
        if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
          thinking.write(chunk.thinking);
        }
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          buffer.write(chunk.content);
        }
        chunkCount++;
        if (chunkCount == 1) {
          debugPrint('[CHAT-DIAG] first chunk: '
              'content=${chunk.content?.length ?? 0} '
              'thinking=${chunk.thinking?.length ?? 0}');
        }
        final now = DateTime.now();
        final shouldUpdate = chunkCount == 1 ||
            lastPlainUiUpdate == null ||
            now.difference(lastPlainUiUpdate) >=
                const Duration(milliseconds: 80);
        if (shouldUpdate) {
          lastPlainUiUpdate = now;
          _streamText = buffer.toString();
          _streamThinking = thinking.toString();
          _streamRevision.value++;
          _scrollToBottom(animate: false);
        }
      }

      debugPrint('[CHAT-DIAG] stream done: chunks=$chunkCount '
          'buffer=${buffer.length} stopped=$_stopRequested mounted=$mounted');
      plainStopwatch.stop();
      final plainSpeed = _formatSpeed(
        chars: buffer.length,
        firstTokenMs: plainFirstTokenMs,
        totalMs: plainStopwatch.elapsedMilliseconds,
      );
      if (mounted) {
        final stopped = _stopRequested || cancellation.isCancelled;
        // 正文为空但有思考内容 = 模型把预算花在思考上了：给出可操作的说明，
        // 而不是留一个空气泡让用户以为"没回复"。
        final emptyWithThinking =
            buffer.isEmpty && thinking.isNotEmpty && !stopped;
        setState(() {
          _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: emptyWithThinking
                ? '（模型把本次预算都用在了思考上，没有输出正文）\n'
                    '可以：① 在参数面板里把「最大生成长度」调大；'
                    '② 或换更小的模型/稍后重试。'
                : (buffer.isEmpty && stopped ? '（已停止生成）' : buffer.toString()),
            thinking: thinking.toString(),
            speed: plainSpeed,
          ));
          _streamText = '';
          _streamThinking = '';
          _isGenerating = false;
          _stopRequested = false;
        });
        await _store.save(_conversation);
      }
    } catch (e, st) {
      debugPrint('[CHAT-DIAG] send threw: $e\n$st');
      final message = e.toString();
      final tooLong = message.contains('too long') ||
          message.contains('Tokenization failed') ||
          message.contains('context');
      if (mounted) {
        setState(() {
          _isGenerating = false;
          final stopped = _stopRequested || cancellation.isCancelled;
          _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: stopped
                ? '（已停止生成）'
                : tooLong
                    ? '这次请求超出上下文长度了。可以：\n'
                        '· 点参数面板里的「立即整理上下文」（把旧内容折叠+摘要）；\n'
                        '· 或把「上下文长度」调大一档；\n'
                        '· 或开一个新对话继续这个话题。\n'
                        '（原始错误：$message）'
                    : '生成失败: $message',
          ));
          _stopRequested = false;
        });
        await _store.save(_conversation);
      }
    }
    if (identical(_requestCancellation, cancellation)) {
      _requestCancellation = null;
    }
    _scrollToBottom();
  }

  /// 粗粒度 token 估算：中文约 1.5 字符/token，英文约 4 字符/token。
  /// （比纯字数准得多；本地拿不到精确 tokenizer 时的业界常规做法。）
  static int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) {
        cjk++;
      } else {
        other++;
      }
    }
    return (cjk / 1.5 + other / 4).ceil();
  }

  int _contextTokens() {
    var total = _estimateTokens(_conversation.summary);
    for (final message in _conversation.messages) {
      total += _estimateTokens(message.text);
      total += _estimateTokens(message.thinking ?? '');
      for (final attachment in message.attachments) {
        total += _estimateTokens(attachment.content ?? '');
      }
    }
    return total;
  }

  /// 触发"摘要"的水位：用户可调阈值（token），或上下文长度的 85%。
  int get _summarizeWatermark {
    // 上限硬约束在上下文 90%：无论用户设多少，都不允许把提示词堆到超限
    // （超限会直接抛 "prompt too long"，之后整段对话都用不了）。
    final ceiling = (_contextSize * 0.9).round();
    final configured = _conversation.settings.autoCompressAtChars;
    if (configured > 0) return configured < ceiling ? configured : ceiling;
    return (_contextSize * 0.85).round();
  }

  /// 触发"轻量折叠"的水位：上下文长度的 70%（不调 LLM，零成本）。
  int get _pruneWatermark => (_contextSize * 0.70).round();

  bool get _needsPrune => _contextTokens() > _pruneWatermark;
  bool get _needsSummarize => _contextTokens() > _summarizeWatermark;

  /// 第一层：轻量折叠（零成本，不调模型）。
  /// 把较早消息里的大块内容（工具输出、思考、附件正文）截短，
  /// 保留用户消息的首行——业界共识：用户诉求最后才动。
  void _pruneOldContent({int keepRecent = 6}) {
    if (_conversation.messages.length <= keepRecent) return;
    final cutoff = _conversation.messages.length - keepRecent;
    var changed = false;
    for (var i = 0; i < cutoff; i++) {
      final message = _conversation.messages[i];
      if (message.text.length <= 400 &&
          (message.thinking == null || message.thinking!.length <= 400)) {
        continue;
      }
      // 用户消息只保留开头（保住诉求），助手长文折叠成摘要行。
      final keep = message.role == 'user' ? 400 : 200;
      final folded = message.text.length > keep
          ? '${message.text.substring(0, keep)}…（已折叠 ${message.text.length - keep} 字）'
          : message.text;
      _conversation.messages[i] = ChatMessageRecord(
        role: message.role,
        text: folded,
        thinking: null,
        attachments: const [],
        toolSteps: const [],
        speed: message.speed,
      );
      changed = true;
    }
    if (changed) {
      debugPrint('[Context] 轻量折叠完成，约 ${_contextTokens()} tokens');
    }
  }

  /// 压缩上下文：保留最近 [keepRecent] 条，其余交给模型总结成一段摘要。
  /// 摘要随对话持久化，之后每次对话都带上它（老消息从发送列表里移除）。
  Future<void> _compressContext(
      {int keepRecent = 8, bool silent = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final messages = _conversation.messages;
    if (messages.length <= keepRecent) {
      if (!silent) {
        messenger.showSnackBar(const SnackBar(
            content: Text('消息还不多，不需要压缩'), duration: Duration(seconds: 2)));
      }
      return;
    }
    final older = messages.sublist(0, messages.length - keepRecent);
    final recent = messages.sublist(messages.length - keepRecent);
    setState(() => _compressing = true);
    try {
      final transcript = older
          .map((m) => '${m.role == 'user' ? '用户' : '助手'}：${m.text}')
          .join('\n');
      // 用户诉求原样保留（压缩也不能丢用户说过什么）。
      final userIntents = older
          .where((m) => m.role == 'user')
          .map((m) => '- ${m.text.replaceAll(RegExp(r'\s+'), ' ').trim()}'
              '${m.text.length > 120 ? '…' : ''}')
          .join('\n');
      final summary = await _engine.generate([
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: '把下面这段对话压缩成要点摘要，保留人物、偏好、'
              '结论、未完成事项与关键数据；不要评论，不要加入新信息。'
              '用简洁的中文短句。这是**增量压缩**：如果已有摘要，'
              '请与它合并去重，不要写成"摘要的摘要"。',
        ),
        LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: transcript.length > 8000
                ? transcript.substring(transcript.length - 8000)
                : transcript),
      ], maxTokens: 400, temp: 0.3).timeout(const Duration(minutes: 3));
      final merged = [
        if (_conversation.summary.isNotEmpty) _conversation.summary,
        if (summary.trim().isNotEmpty) summary.trim(),
      ].join('\n');
      final withIntents =
          userIntents.isEmpty ? merged : '$merged\n\n用户此前提过的诉求：\n$userIntents';
      if (!mounted) return;
      setState(() {
        _conversation.summary = withIntents;
        _conversation.messages
          ..clear()
          ..addAll(recent);
        _compressing = false;
      });
      await _store.save(_conversation);
      messenger.showSnackBar(SnackBar(
        content: Text('已压缩 ${older.length} 条早期消息为摘要'
            '（保留最近 ${recent.length} 条）'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) setState(() => _compressing = false);
      messenger.showSnackBar(
          SnackBar(content: Text('压缩失败：$e'), backgroundColor: AppColors.error));
    }
  }

  /// 速度行：tok/s（按字符估算，CJK 约 1.6 字符/token）× 耗时 × 首字延迟。
  String _formatSpeed({
    required int chars,
    required int firstTokenMs,
    required int totalMs,
  }) {
    if (chars <= 0 || totalMs <= 0) return '';
    final tokens = (chars / 1.6).clamp(1, 1 << 30);
    final seconds = totalMs / 1000;
    final rate = seconds > 0 ? tokens / seconds : 0;
    final first = firstTokenMs >= 0
        ? ' · 首字 ${(firstTokenMs / 1000).toStringAsFixed(2)}s'
        : '';
    return '${rate.toStringAsFixed(1)} tok/s · ${seconds.toStringAsFixed(1)}s'
        '$first';
  }

  /// 应用调参后重新加载模型（几秒）。
  Future<void> _reloadForTuning() async {
    try {
      await _engine.loadModel(widget.modelPath,
          contextSize: _contextSize, force: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('已应用并重新加载模型'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('重新加载失败：$e'), backgroundColor: AppColors.error));
      }
    }
  }

  String _shorten(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  /// 空状态的能力说明。判定顺序（与引擎实际能力保持一致）：
  /// 引擎已就绪且确认能看图 → 多模态已启用；
  /// 本身属于视觉家族（无论引擎此刻状态）→ 多模态，区分投影是否已备好；
  /// 其余 → 纯文本。此前直接读引擎状态，在"引擎还装着上一个模型"时
  /// 会把 gemma-3-4b 这类多模态模型错标成"纯文本"。
  String _emptyStateHint() {
    const fileHint = '（txt / md / json / csv…）';
    if (_engine.isReadyFor(widget.modelPath, contextSize: _contextSize)) {
      if (_engine.supportsVision) {
        return '多模态模型：支持附加图片和文本文件';
      }
      if (_engine.hasVisionCandidate) {
        return '多模态模型（视觉投影已下载）：发图片时会加载看图能力';
      }
    }
    if (ModelCapabilities.isVisionFamily(widget.modelPath)) {
      return '多模态模型：尚未挂载视觉投影——'
          '发一张图片即可引导绑定，或到「模型」页给该模型补装投影';
    }
    return '纯文本模型：支持附加文本文件$fileHint';
  }

  /// 手动把磁盘上的视觉投影绑定到当前模型。
  Future<bool> _bindProjector() async {
    final messenger = ScaffoldMessenger.of(context);
    final files = <File>[];
    for (final file in await ModelDownloadService.listProjectors()) {
      final owner =
          await ModelStorageSettings.projectorOwner(file.uri.pathSegments.last);
      if (owner == null || owner == widget.modelPath.split('/').last) {
        files.add(file);
      }
    }
    if (!mounted) return false;
    if (files.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('设备上还没有视觉投影文件：'
            '到「模型」页给多模态模型点「补装视觉投影」'),
      ));
      return false;
    }
    final picked = await showDialog<File>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择要绑定的视觉投影'),
        children: [
          for (final file in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, file),
              child: Text(file.uri.pathSegments.last,
                  style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
    if (picked == null) return false;
    final mainName = widget.modelPath.split('/').last;
    final paired = await ModelStorageSettings.pairProjector(
        mainName, picked.uri.pathSegments.last);
    if (!paired) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这个投影已经配给其他主模型，不能重复挂载'),
        backgroundColor: AppColors.warning,
      ));
      return false;
    }
    // 重新加载模型，让引擎按新配对挂上投影。
    try {
      await _engine
          .loadModel(widget.modelPath, contextSize: _contextSize, force: true)
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      debugPrint('[Chat] 绑定后重载失败: $e');
      return false;
    }
    final visionReady = _engine.hasVisionCandidate
        ? await _engine.ensureVision()
        : _engine.supportsVision;
    return visionReady;
  }

  /// 不能看图时的说明与分流。
  /// 返回 'text'（移除图片继续）、'bind'（去绑定投影）或 null（取消）。
  Future<String?> _confirmTextOnly() {
    final isVisionFamily = ModelCapabilities.isVisionFamily(widget.modelName);
    final reason = _engine.projectorError != null
        ? '视觉投影加载失败（可能是投影与模型不匹配或文件损坏）：'
            '${_engine.projectorError}'
        : isVisionFamily
            ? '这个模型属于多模态家族，但同目录没有找到与它匹配的视觉投影文件'
                '（mmproj-*.gguf）。投影是模型专用的，不能拿别的模型的来用。'
            : '这个模型是纯文本模型，本身没有视觉能力。';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这个模型现在看不了图'),
        content: Text(
          '「${widget.modelName}」：$reason\n\n'
          '怎么办：\n'
          '· 已经下过视觉投影 → 点「绑定视觉投影」选一个文件即可；\n'
          '· 还没下 → 到「模型」页给多模态模型点「补装视觉投影」；\n'
          '· 只是想继续聊 → 移除图片，只发文字（文本能力不受影响）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'bind'),
            child: const Text('绑定视觉投影'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'text'),
            child: const Text('移除图片，继续发文字'),
          ),
        ],
      ),
    );
  }

  /// 把对话记录转成引擎消息（附件按类型处理）。
  List<LlamaChatMessage> _buildEngineMessages({String memorySection = ''}) {
    final messages = <LlamaChatMessage>[];
    final systemText = [
      if (_conversation.settings.systemPrompt.trim().isNotEmpty)
        _conversation.settings.systemPrompt.trim(),
      if (_conversation.summary.isNotEmpty)
        '以下是本次对话更早内容的摘要（请当作已知背景）：\n${_conversation.summary}',
      if (memorySection.isNotEmpty) memorySection,
    ].join('\n\n');
    if (systemText.isNotEmpty) {
      messages.add(LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: systemText,
      ));
    }
    for (final record in _conversation.messages) {
      final role =
          record.role == 'user' ? LlamaChatRole.user : LlamaChatRole.assistant;

      final images = _engine.supportsVision
          ? record.attachments
              .where((a) => a.type == 'image' && a.path != null)
              .toList()
          : const <ChatAttachment>[];
      final textFiles = record.attachments
          .where((a) => a.type == 'text' && (a.content?.isNotEmpty ?? false))
          .toList();

      // 文本文件内容内联到提示词。
      var text = record.text;
      for (final file in textFiles) {
        final content = file.content!;
        final clipped = content.length > 8000
            ? '${content.substring(0, 8000)}\n…（已截断）'
            : content;
        text = '$text\n\n【附件：${file.name}】\n$clipped';
      }

      if (images.isNotEmpty) {
        // 多模态消息：图片 + 文本。
        messages.add(LlamaChatMessage.withContent(
          role: role,
          content: [
            if (text.trim().isNotEmpty) LlamaTextContent(text.trim()),
            for (final image in images) LlamaImageContent(path: image.path),
          ],
        ));
      } else {
        messages.add(LlamaChatMessage.fromText(role: role, text: text));
      }
    }
    return messages;
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const [
        'png', 'jpg', 'jpeg', 'webp', // 图片
        'txt', 'md', 'json', 'csv', 'log', 'yaml', 'yml', // 文本
      ],
    );
    if (result == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final ext = (file.extension ?? '').toLowerCase();
      const imageExts = {'png', 'jpg', 'jpeg', 'webp'};
      if (imageExts.contains(ext)) {
        _pendingAttachments
            .add(ChatAttachment(name: file.name, type: 'image', path: path));
      } else {
        try {
          final content = await File(path).readAsString();
          _pendingAttachments.add(
              ChatAttachment(name: file.name, type: 'text', content: content));
        } catch (e) {
          messenger.showSnackBar(SnackBar(
              content: Text('读取 ${file.name} 失败: $e'),
              backgroundColor: AppColors.error));
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 全屏高度的面板会顶到状态栏（标题与时间/电量重叠）。
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final settings = _conversation.settings;
          final supportsThinking =
              ModelCapabilities.supportsThinking(widget.modelName);
          final secondary = Theme.of(sheetContext).brightness == Brightness.dark
              ? AppColors.darkTextSecondary
              : AppColors.textSecondary;
          void update(ChatGenerationSettings next) {
            setSheetState(() {});
            setState(() => _conversation.settings = next);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('生成参数',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    _sliderRow(
                      label: '温度（越高越随机）',
                      value: settings.temp,
                      min: 0,
                      max: 2,
                      onChanged: (v) => update(settings.copyWith(temp: v)),
                    ),
                    _sliderRow(
                      label: 'Top-P（采样范围）',
                      value: settings.topP,
                      min: 0.1,
                      max: 1.0,
                      onChanged: (v) => update(settings.copyWith(topP: v)),
                    ),
                    _sliderRow(
                      label: '最大生成长度',
                      value: settings.maxTokens.toDouble(),
                      min: 256,
                      max: 8192,
                      divisions: 31,
                      display: '${settings.maxTokens} tokens',
                      onChanged: (v) =>
                          update(settings.copyWith(maxTokens: v.round())),
                    ),
                    DropdownButtonFormField<LocalLlmPreset>(
                      initialValue: LocalLlmTuning.preset,
                      decoration: InputDecoration(
                        labelText: '性能档位（改完下一条消息生效）',
                        helperText: LocalLlmTuning.describe(),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final preset in LocalLlmPreset.values)
                          DropdownMenuItem(
                              value: preset, child: Text(preset.label)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() {});
                        LocalLlmTuning.setPreset(value).then((_) async {
                          // 重新加载模型让新参数生效。
                          try {
                            await _engine.loadModel(widget.modelPath,
                                contextSize: _contextSize, force: true);
                          } catch (e) {
                            debugPrint('[Tuning] 重载失败: $e');
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: _contextSize,
                      decoration: const InputDecoration(
                        labelText: '上下文长度（越大记住的越多）',
                        helperText: '改完下一条消息生效（会重新加载模型）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 4096, child: Text('4096 · 省内存')),
                        DropdownMenuItem(value: 8192, child: Text('8192 · 日常')),
                        DropdownMenuItem(
                            value: 16384, child: Text('16384 · 长对话')),
                        DropdownMenuItem(
                            value: 32768, child: Text('32768 · 长文档')),
                      ],
                      onChanged: (value) async {
                        if (value == null) return;
                        setSheetState(() {});
                        setState(() => _contextSize = value);
                        // 之前只改状态不重载 → helperText 说"会重新加载"但实际没生效。
                        try {
                          await _engine.loadModel(widget.modelPath,
                              contextSize: value, force: true);
                        } catch (e) {
                          debugPrint('[Chat] 切换上下文长度失败: $e');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_toolsEnabled ? '使用工具（插件）：已开启' : '使用工具（插件）'),
                      subtitle:
                          const Text('联网搜索 / 新闻 / 抓网页 / 算术 / HTML / 待办 / 找模型…'
                              '（与右上角插件面板同一个开关）'),
                      value: _toolsEnabled,
                      onChanged: (v) {
                        // 先刷新面板本身，再通知页面（否则点了看不到变化）。
                        setSheetState(() {});
                        setState(() => _toolsEnabled = v);
                        unawaited(ToolRegistry.setMasterEnabled(v));
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('深度思考'),
                      subtitle: Text(
                        supportsThinking
                            ? '推理模型会先输出思考过程（可折叠查看）'
                            : '未识别为推理模型；这类模型仍可能自带思考过程，'
                                '可用下面的开关强制启用思考预算',
                      ),
                      value: settings.thinkingEnabled,
                      onChanged: (v) =>
                          update(settings.copyWith(thinkingEnabled: v)),
                    ),
                    if (!supportsThinking)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '提示：Spark-X2.5 等模型本身就会输出思考过程，'
                          '开关关掉也不会消失，只是不再额外给思考预算。',
                          style: TextStyle(fontSize: 11, color: secondary),
                        ),
                      ),
                    DropdownButtonFormField<int>(
                      initialValue: settings.autoCompressAtChars,
                      decoration: const InputDecoration(
                        labelText: '上下文摘要阈值（0=按上下文 85% 自动）',
                        helperText: '对话超过这个长度就自动把早期消息压成摘要',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('自动（上下文 85%）')),
                        DropdownMenuItem(
                            value: 1500, child: Text('1500 tokens（省内存）')),
                        DropdownMenuItem(
                            value: 3000, child: Text('3000 tokens（默认）')),
                        DropdownMenuItem(
                            value: 6000, child: Text('6000 tokens')),
                        DropdownMenuItem(
                            value: 12000, child: Text('12000 tokens（长会话）')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        update(settings.copyWith(autoCompressAtChars: value));
                      },
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _compressing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.compress, size: 18),
                        label: Text(
                            _compressing ? '压缩中…' : '立即整理上下文（折叠旧工具输出 + 增量摘要）'),
                        onPressed:
                            _compressing ? null : () => _compressContext(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title:
                          const Text('高级性能选项', style: TextStyle(fontSize: 13)),
                      subtitle: Text('GPU 层数 / 线程 / FlashAttention / KV 量化',
                          style: TextStyle(fontSize: 11, color: secondary)),
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: LocalLlmTuning.gpuLayersOverride ?? -1,
                          decoration: const InputDecoration(
                            labelText: 'GPU 卸载层数',
                            helperText: '-1=自动（推荐）· 0=纯 CPU · 层数越多越快也越吃显存',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: -1, child: Text('自动（推荐）')),
                            DropdownMenuItem(value: 0, child: Text('0（纯 CPU）')),
                            DropdownMenuItem(value: 16, child: Text('16 层')),
                            DropdownMenuItem(value: 24, child: Text('24 层')),
                            DropdownMenuItem(value: 32, child: Text('32 层')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            setSheetState(() {});
                            await LocalLlmTuning.setAdvanced(gpuLayers: v);
                            await _reloadForTuning();
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: LocalLlmTuning.threadsOverride ?? 0,
                          decoration: const InputDecoration(
                            labelText: '生成线程数',
                            helperText: '0=自动；手机通常 4 个线程最优（生成受内存带宽限制）',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('自动（推荐）')),
                            DropdownMenuItem(value: 2, child: Text('2')),
                            DropdownMenuItem(value: 4, child: Text('4')),
                            DropdownMenuItem(value: 6, child: Text('6')),
                            DropdownMenuItem(value: 8, child: Text('8')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            setSheetState(() {});
                            await LocalLlmTuning.setAdvanced(threads: v);
                            await _reloadForTuning();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('FlashAttention',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text('长上下文更快更省内存；个别机型可能不稳',
                              style: TextStyle(fontSize: 11)),
                          value: LocalLlmTuning.flashAttention,
                          onChanged: (v) async {
                            setSheetState(() {});
                            await LocalLlmTuning.setAdvanced(flashAttention: v);
                            await _reloadForTuning();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('KV cache 量化（q8_0）',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text('省一半 KV 内存；部分机型反而更慢，默认关',
                              style: TextStyle(fontSize: 11)),
                          value: LocalLlmTuning.kvQuantized,
                          onChanged: (v) async {
                            setSheetState(() {});
                            await LocalLlmTuning.setAdvanced(kvQuantized: v);
                            await _reloadForTuning();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('投机解码（n-gram 自推测）',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text(
                              '零额外内存；代码/HTML 等重复多的输出可快 1.5~2 倍。'
                              '不支持时自动降级，不影响使用',
                              style: TextStyle(fontSize: 11)),
                          value: LocalLlmTuning.speculativeNgram,
                          onChanged: (v) async {
                            setSheetState(() {});
                            await LocalLlmTuning.setAdvanced(
                                speculativeNgram: v);
                            await _reloadForTuning();
                          },
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: const Text('应用并重新加载模型'),
                            onPressed: _reloadForTuning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('系统提示词', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: settings.systemPrompt,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '例如：你是一个严谨的 API 调试助手…（留空则不发送）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          update(settings.copyWith(systemPrompt: v)),
                    ),
                    const SizedBox(height: 8),
                    Text('参数与系统提示词按对话保存，下次继续对话时沿用。',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(sheetContext).brightness ==
                                    Brightness.dark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    String? display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(display ?? value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 12, color: AppColors.primary)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions ?? 20,
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// 新对话：**原地**换一个会话，复用已加载的引擎。
  /// 之前用 pushReplacement 重建页面 → 引擎重新加载（大模型要几十秒）。
  void _newConversation() {
    setState(() {
      _conversation = ChatConversation(
        id: const Uuid().v4(),
        title: widget.modelName,
        modelPath: widget.modelPath,
        modelName: widget.modelName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
      );
      _memorySectionCache = null;
      _streamText = '';
      _streamThinking = '';
      _pendingAttachments.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已开启新对话（模型保持加载，无需等待）'), duration: Duration(seconds: 2)));
  }

  void _openConversationList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationListScreen(
          modelPath: widget.modelPath,
          modelName: widget.modelName,
        ),
      ),
    ).then((_) {
      // 从列表返回时刷新当前对话（可能被删除或在列表里切换过）。
      _store.load(_conversation.id).then((loaded) {
        if (loaded != null && mounted) {
          setState(() => _conversation = loaded);
        }
      });
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final offset = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(offset);
      }
    });
  }

  @override
  void dispose() {
    _requestCancellation?.cancel();
    _requestCancellation = null;
    _controller.dispose();
    _scrollController.dispose();
    _streamRevision.dispose();
    // 已注册的引擎留给工具、诊断和下一次聊天复用；只有初始化失败、从未
    // 注册过的页面实例才在退出时释放。释放动作等待加载/生成结束，避免
    // native 层在 Vulkan 编译期间被销毁。
    if (AiService.registeredLocalEngine != _engine && _ownsEngine) {
      unawaited(_engine.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final modelName = widget.modelName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // _conversation 由异步 _init 赋值：就绪前必须回退到入参，
            // 否则 late 字段未初始化会抛错（整页 "本区域渲染出错"）。
            Text(_modelReady ? _conversation.title : widget.modelName,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
                '$modelName'
                '${_modelReady && _engine.isReadyFor(widget.modelPath, contextSize: _contextSize) ? (_engine.supportsVision ? ' · 多模态（看图已启用）' : (_engine.hasVisionCandidate ? ' · 多模态（投影已就绪）' : (ModelCapabilities.isVisionFamily(widget.modelPath) ? ' · 多模态（未挂投影）' : ' · 纯文本'))) : ''}'
                '${_modelReady ? ' · 上下文 ${(_contextTokens() / _contextSize * 100).clamp(0, 999).toStringAsFixed(0)}%' : ''}'
                '${ModelCapabilities.supportsThinking(widget.modelName) ? ' · 支持思考' : ''}',
                style: TextStyle(fontSize: 11, color: secondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新对话',
            onPressed: _isGenerating ? null : _newConversation,
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: '历史对话',
            onPressed: _openConversationList,
          ),
          IconButton(
            // AppBar 是蓝色：开启时用暖色高亮，否则图标会"融进背景"看不见。
            icon: Icon(
              _toolsEnabled ? Icons.extension : Icons.extension_off,
              color: _toolsEnabled ? AppColors.warning : null,
            ),
            tooltip: _toolsEnabled ? '插件已开启（点击设置）' : '插件未开启（点击设置）',
            onPressed: () => showToolPanel(
              context,
              toolsEnabled: _toolsEnabled,
              onToolsChanged: (v) => setState(() => _toolsEnabled = v),
              visionAvailable: _engine.supportsVision,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '生成参数',
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 44, color: AppColors.error),
                    const SizedBox(height: 12),
                    const Text('模型加载失败',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                      onPressed: () {
                        setState(() => _loadError = null);
                        _init();
                      },
                    ),
                  ],
                ),
              ),
            )
          : !_modelReady
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('正在加载 ${widget.modelName}…',
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 6),
                      const Text('大模型首次加载可能需要一到几分钟，请稍候',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _conversation.messages.isEmpty && !_isGenerating
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_outline,
                                      size: 48, color: secondary),
                                  const SizedBox(height: 12),
                                  Text('与 $modelName 开始对话',
                                      style: TextStyle(color: secondary)),
                                  const SizedBox(height: 4),
                                  Text(_emptyStateHint(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11, color: secondary)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _conversation.messages.length +
                                  (_isGenerating ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _conversation.messages.length) {
                                  return _buildStreamingBubble(isDark);
                                }
                                return _buildMessageBubble(index,
                                    _conversation.messages[index], isDark);
                              },
                            ),
                    ),
                    if (_compressing)
                      Container(
                        width: double.infinity,
                        color: AppColors.secondary.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: const Row(
                          children: [
                            SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('正在压缩上下文…', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    if (_switchingModel)
                      Container(
                        width: double.infinity,
                        color: AppColors.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: const Row(
                          children: [
                            SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  '正在切换/加载模型（大模型可能需要几分钟），'
                                  '完成后自动继续发送…',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    if (_enablingVision)
                      Container(
                        width: double.infinity,
                        color: AppColors.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: const Row(
                          children: [
                            SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('正在启用视觉投影（首次需几秒）…',
                                style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    if (_pendingAttachments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (var i = 0; i < _pendingAttachments.length; i++)
                              Chip(
                                avatar: Icon(
                                  _pendingAttachments[i].type == 'image'
                                      ? Icons.image
                                      : Icons.description,
                                  size: 16,
                                ),
                                label: Text(_pendingAttachments[i].name,
                                    style: const TextStyle(fontSize: 11)),
                                onDeleted: () => setState(
                                    () => _pendingAttachments.removeAt(i)),
                              ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file),
                              tooltip: '添加附件（图片/文本）',
                              onPressed: _isGenerating ? null : _pickAttachment,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: InputDecoration(
                                  hintText: '输入消息…',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: _isGenerating
                                  ? AppColors.error
                                  : AppColors.primary,
                              child: IconButton(
                                icon: Icon(
                                    _isGenerating ? Icons.stop : Icons.send,
                                    color: Colors.white,
                                    size: 20),
                                tooltip: _isGenerating ? '停止生成' : '发送',
                                onPressed: _isGenerating
                                    ? () {
                                        setState(() => _stopRequested = true);
                                        // 真正中断底层推理（工具模式也生效）。
                                        _requestCancellation?.cancel();
                                      }
                                    : _send,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStreamingBubble(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: _streamRevision,
          builder: (context, _, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isGenerating &&
                  _streamText.isEmpty &&
                  _streamThinking.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '思考中…（已 ${_streamThinking.length} 字，'
                      '点击气泡上方「查看思考过程」可展开）',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary)),
                ),
              if (_pendingSteps.isNotEmpty)
                _thinkingPanel(
                  [
                    for (final step in _pendingSteps)
                      '${step.tool}(${step.argsLabel})：${_shorten(step.result)}',
                  ].join('\n\n'),
                  -2,
                  isDark,
                  title: '工具调用中（${_pendingSteps.length} 步）',
                ),
              if (_streamThinking.isNotEmpty)
                _thinkingPanel(_streamThinking, -1, isDark),
              Text(_streamText.isEmpty && _streamThinking.isNotEmpty
                  ? '（思考中…）'
                  : (_streamText.isEmpty ? '…' : _streamText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(int index, ChatMessageRecord record, bool isDark) {
    final isUser = record.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.primary
              : (isDark ? AppColors.darkSurface : AppColors.background),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 附件标签
            if (record.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final a in record.attachments)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isUser ? Colors.white : AppColors.primary)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                a.type == 'image'
                                    ? Icons.image
                                    : Icons.description,
                                size: 12,
                                color:
                                    isUser ? Colors.white : AppColors.primary),
                            const SizedBox(width: 4),
                            Text(a.name,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isUser
                                        ? Colors.white
                                        : AppColors.primary)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            // 工具调用过程（默认折叠，可点开）
            if (!isUser && record.toolSteps.isNotEmpty)
              _thinkingPanel(
                  record.toolSteps.join('\n\n'), index + 100000, isDark,
                  title: '查看工具调用（${record.toolSteps.length} 步）'),
            // 思考过程（默认折叠，可点开）
            if (!isUser &&
                record.thinking != null &&
                record.thinking!.isNotEmpty)
              _thinkingPanel(record.thinking!, index, isDark),
            if (!isUser && (record.speed ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(record.speed!,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary)),
              ),
            if (record.text.isNotEmpty)
              ChatMessageBody(
                text: record.text,
                isUser: isUser,
                textColor: isUser
                    ? Colors.white
                    : (isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary),
              ),
          ],
        ),
      ),
    );
  }

  /// 思考过程面板：默认折叠，点击展开/收起。
  Widget _thinkingPanel(String thinking, int index, bool isDark,
      {String? title}) {
    // 生成中的思考面板（index == -1）默认展开：否则用户只看到"没动静"。
    final expanded = index == -1
        ? !_expandedThinking.contains(-1)
        : _expandedThinking.contains(index);
    final color =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedThinking.remove(index);
              } else {
                _expandedThinking.add(index);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(expanded ? '收起' : (title ?? '查看思考过程'),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.primary)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
              child: SelectableText(
                thinking,
                style: TextStyle(fontSize: 12, height: 1.4, color: color),
              ),
            ),
        ],
      ),
    );
  }
}
