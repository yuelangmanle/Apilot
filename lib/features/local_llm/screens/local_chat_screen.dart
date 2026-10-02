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
import '../../api_management/providers/api_provider.dart';
import '../../../core/services/local_llm/chat_conversation_store.dart';
import '../../../core/services/local_llm/model_capabilities.dart';
import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../shared/theme/color_scheme.dart';
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
  late ChatConversation _conversation;

  bool _isGenerating = false;
  bool _modelReady = false;
  bool _stopRequested = false;
  bool _enablingVision = false;
  bool _toolsEnabled = false;
  final List<agent.AgentStep> _pendingSteps = [];
  String _streamText = '';
  String _streamThinking = '';
  final Set<int> _expandedThinking = {};

  @override
  void initState() {
    super.initState();
    _engine = LocalLlmEngine();
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
        await _engine.loadModel(widget.modelPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('模型加载失败: $e'),
            backgroundColor: AppColors.error,
          ));
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

    debugPrint('[CHAT-DIAG] send: text="${text.length > 20 ? '${text.substring(0, 20)}…' : text}" '
        'attachments=${_pendingAttachments.length} tools=$_toolsEnabled '
        'engineLoaded=${_engine.isLoaded}');
    // 图片处理：模型能看图就直接发；有投影候选就先按需启用；
    // 都没有则讲清楚让用户决定，绝不让引擎抛错（用户看不懂）。
    final hasImage =
        _pendingAttachments.any((a) => a.type == 'image');
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
        final useTextOnly = await _confirmTextOnly();
        if (useTextOnly != true) return;
        setState(
            () => _pendingAttachments.removeWhere((a) => a.type == 'image'));
        text = _controller.text.trim();
        if (text.isEmpty && _pendingAttachments.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('图片已移除，请输入文字后再发送')));
          }
          return;
        }
      }
    }

    // 长期记忆：① 用户明确说"记住…"就自动入库；
    // ② 开了记忆插件时，把相关记忆注入系统提示词。
    if (ToolRegistry.isCategoryEnabled('memory')) {
      final explicit = MemoryStore.extractExplicitMemory(text);
      if (explicit != null) {
        await MemoryStore.save(explicit);
      }
    }

    final attachments = List<ChatAttachment>.from(_pendingAttachments);
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
    if (_toolsEnabled) {
      _pendingSteps.clear();
      final history = <agent.ChatTurn>[
        for (final record in _conversation.messages
            .where((m) => m.role == 'user' || m.role == 'assistant')
            .toList()
            .take(_conversation.messages.length - 1))
          agent.ChatTurn(isUser: record.role == 'user', text: record.text),
      ];
      final result = await agent.AgentRunner.run(
        userPrompt: text,
        configs: configs,
        localEngine: _engine,
        history: history.length > 6
            ? history.sublist(history.length - 6)
            : history,
        onStep: (step) {
          if (mounted) setState(() => _pendingSteps.add(step));
        },
      );
      if (mounted) {
        setState(() {
          _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: result.text.isEmpty
                ? (result.error ?? '（没有返回内容）')
                : result.text,
            toolSteps: [
              for (final step in result.steps)
                '${step.tool}(${step.argsLabel})：${_shorten(step.result)}',
            ],
          ));
          _isGenerating = false;
        });
        await _store.save(_conversation);
      }
      _scrollToBottom();
      return;
    }

    try {
      // 相关记忆注入（仅在记忆插件开启时）。
      var memorySection = '';
      if (ToolRegistry.isCategoryEnabled('memory')) {
        memorySection = await MemoryStore.buildPromptSection(text);
      }
      final messages = _buildEngineMessages(memorySection: memorySection);
      debugPrint('[CHAT-DIAG] messages=${messages.length} roles='
          '${messages.map((m) => m.role).toList()}');
      final buffer = StringBuffer();
      final thinking = StringBuffer();
      var chunkCount = 0;

      await for (final chunk in _engine.generateStream(
        messages,
        maxTokens: _conversation.settings.maxTokens,
        temp: _conversation.settings.temp,
        topP: _conversation.settings.topP,
        thinkingEnabled: _conversation.settings.thinkingEnabled &&
            ModelCapabilities.supportsThinking(widget.modelName),
        // 关闭思考时对 Qwen3 系追加 /no_think，避免预算全被思考吃掉。
        suppressThinking: !_conversation.settings.thinkingEnabled,
      )) {
        if (!mounted) return;
        if (_stopRequested) break;
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
        setState(() {
          _streamText = buffer.toString();
          _streamThinking = thinking.toString();
        });
        _scrollToBottom();
      }

      debugPrint('[CHAT-DIAG] stream done: chunks=$chunkCount '
          'buffer=${buffer.length} stopped=$_stopRequested mounted=$mounted');
      if (mounted) {
        final stopped = _stopRequested;
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
                : (buffer.isEmpty && stopped
                    ? '（已停止生成）'
                    : buffer.toString()),
            thinking: thinking.toString(),
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
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _conversation.messages.add(
              ChatMessageRecord(role: 'assistant', text: '生成失败: $e'));
        });
      }
    }
    _scrollToBottom();
  }

  String _shorten(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  /// 不能看图时的说明与分流。
  Future<bool?> _confirmTextOnly() {
    final isVisionFamily =
        ModelCapabilities.isVisionFamily(widget.modelName);
    final reason = _engine.projectorError != null
        ? '视觉投影加载失败（可能是投影与模型不匹配或文件损坏）：'
            '${_engine.projectorError}'
        : isVisionFamily
            ? '这个模型属于多模态家族，但同目录没有找到与它匹配的视觉投影文件'
                '（mmproj-*.gguf）。投影是模型专用的，不能拿别的模型的来用。'
            : '这个模型是纯文本模型，本身没有视觉能力。';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这个模型现在看不了图'),
        content: Text(
          '「${widget.modelName}」：$reason\n\n'
          '怎么办：\n'
          '· 想看图 → 到「模型」页下载多模态模型（Gemma 3 4B / Qwen2.5-VL 等），'
          '下载它会一起带上匹配的视觉投影；\n'
          '· 只是想继续聊 → 移除图片，只发文字（文本能力完全不受影响）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
      if (memorySection.isNotEmpty) memorySection,
    ].join('\n\n');
    if (systemText.isNotEmpty) {
      messages.add(LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: systemText,
      ));
    }
    for (final record in _conversation.messages) {
      final role = record.role == 'user'
          ? LlamaChatRole.user
          : LlamaChatRole.assistant;

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
            for (final image in images)
              LlamaImageContent(path: image.path),
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
        _pendingAttachments.add(
            ChatAttachment(name: file.name, type: 'image', path: path));
      } else {
        try {
          final content = await File(path).readAsString();
          _pendingAttachments.add(ChatAttachment(
              name: file.name, type: 'text', content: content));
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final settings = _conversation.settings;
          final supportsThinking =
              ModelCapabilities.supportsThinking(widget.modelName);
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
                      onChanged: (v) => update(
                          settings.copyWith(maxTokens: v.round())),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用工具（插件）'),
                      subtitle: const Text('联网搜索 / 抓网页 / 算术 / 存 HTML / 查 App 数据'),
                      value: _toolsEnabled,
                      onChanged: (v) => setState(() => _toolsEnabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('深度思考'),
                      subtitle: Text(
                        supportsThinking
                            ? '推理模型会先输出思考过程（可折叠查看）'
                            : '当前模型不支持深度思考，开关已禁用',
                      ),
                      value: supportsThinking && settings.thinkingEnabled,
                      onChanged: supportsThinking
                          ? (v) =>
                              update(settings.copyWith(thinkingEnabled: v))
                          : null,
                    ),
                    const SizedBox(height: 8),
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
                style: const TextStyle(
                    fontSize: 12, color: AppColors.primary)),
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

  void _newConversation() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LocalChatScreen(
          modelPath: widget.modelPath,
          modelName: widget.modelName,
        ),
      ),
    );
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    // 共享引擎指向本页实例时先摘掉，避免其他 AI 功能用到已释放的引擎。
    if (AiService.sharedLocalEngine == _engine) {
      AiService.registerLocalEngine(null);
    }
    _engine.dispose();
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
                '${_modelReady ? ' · ${_engine.supportsVision ? '多模态' : '纯文本'}' : ''}'
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
            icon: Icon(_toolsEnabled ? Icons.extension : Icons.extension_off,
                color: _toolsEnabled ? AppColors.primary : null),
            tooltip: _toolsEnabled ? '插件已开启（点击逐项设置）' : '插件已关闭',
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
      body: !_modelReady
          ? const Center(child: CircularProgressIndicator())
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
                              Text(
                                  _engine.supportsVision
                                      ? '多模态模型：支持附加图片和文本文件'
                                      : '纯文本模型：支持附加文本文件'
                                          '（txt / md / json / csv…）',
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
                            return _buildMessageBubble(
                                index, _conversation.messages[index], isDark);
                          },
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
                            child: CircularProgressIndicator(strokeWidth: 2)),
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
                        for (var i = 0;
                            i < _pendingAttachments.length;
                            i++)
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
                                ? () => setState(() => _stopRequested = true)
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
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            if (_streamThinking.isNotEmpty) _thinkingPanel(_streamThinking, -1, isDark),
            Text(_streamText.isEmpty && _streamThinking.isNotEmpty
                ? '（思考中…）'
                : (_streamText.isEmpty ? '…' : _streamText)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
      int index, ChatMessageRecord record, bool isDark) {
    final isUser = record.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
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
                                color: isUser
                                    ? Colors.white
                                    : AppColors.primary),
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
              _thinkingPanel(record.toolSteps.join('\n\n'), index + 100000,
                  isDark, title: '查看工具调用（${record.toolSteps.length} 步）'),
            // 思考过程（默认折叠，可点开）
            if (!isUser &&
                record.thinking != null &&
                record.thinking!.isNotEmpty)
              _thinkingPanel(record.thinking!, index, isDark),
            if (record.text.isNotEmpty)
              SelectableText(
                record.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isUser
                      ? Colors.white
                      : (isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 思考过程面板：默认折叠，点击展开/收起。
  Widget _thinkingPanel(String thinking, int index, bool isDark,
      {String? title}) {
    final expanded = _expandedThinking.contains(index);
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                      expanded
                          ? '收起'
                          : (title ??
                              '查看思考过程'),
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
              padding:
                  const EdgeInsets.only(left: 10, right: 10, bottom: 10),
              child: SelectableText(
                thinking,
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: color),
              ),
            ),
        ],
      ),
    );
  }
}
