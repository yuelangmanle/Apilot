import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/api_config.dart';
import 'package:provider/provider.dart';
import '../../../core/services/ai/agent_runner.dart' as agent;
import '../../../core/services/ai/memory_store.dart';
import '../../../core/services/ai/tool_registry.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/local_llm/chat_conversation_store.dart';
import '../../../shared/theme/color_scheme.dart';
import '../widgets/chat_code_block.dart';
import '../widgets/tool_panel.dart';
import '../../api_management/providers/api_provider.dart';
import 'conversation_list_screen.dart';

/// 云端 API 多轮对话：直接对着某个 API 配置聊天。
///
/// 与本地对话共用对话存储（按配置隔离），支持流式输出、思考过程折叠、
/// 生成参数、系统提示词与历史对话。
class ApiChatScreen extends StatefulWidget {
  final ApiConfig apiConfig;
  final String? conversationId;

  const ApiChatScreen({
    super.key,
    required this.apiConfig,
    this.conversationId,
  });

  /// 对话存储里区分云端/本地：云端用 cloud:<配置id> 作为 modelPath。
  static String conversationKeyFor(String configId) => 'cloud:$configId';

  @override
  State<ApiChatScreen> createState() => _ApiChatScreenState();
}

class _ApiChatScreenState extends State<ApiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _store = ChatConversationStore();
  final _apiService = ApiService();

  late ChatConversation _conversation;
  late String _selectedModel;

  bool _ready = false;
  bool _isGenerating = false;
  bool _stopRequested = false;
  String _streamText = '';
  String _streamThinking = '';
  final Set<int> _expandedThinking = {};
  int _requestId = 0;
  bool _toolsEnabled = ToolRegistry.masterEnabled;
  final List<agent.AgentStep> _pendingSteps = [];

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.apiConfig.selectedModel ??
        (widget.apiConfig.models.isEmpty ? '' : widget.apiConfig.models.first);
    _init();
  }

  Future<void> _init() async {
    ChatConversation? loaded;
    if (widget.conversationId != null) {
      loaded = await _store.load(widget.conversationId!);
    }
    _conversation = loaded ??
        ChatConversation(
          id: const Uuid().v4(),
          title: widget.apiConfig.name,
          modelPath: ApiChatScreen.conversationKeyFor(widget.apiConfig.id),
          modelName: widget.apiConfig.name,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: [],
        );
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _controller.clear();
    final requestId = ++_requestId;
    setState(() {
      _conversation.messages
          .add(ChatMessageRecord(role: 'user', text: text));
      _isGenerating = true;
      _stopRequested = false;
      _streamText = '';
      _streamThinking = '';
    });
    _scrollToBottom();

    // 工具模式：走 Agent 循环（搜索/抓网页/算术/存 HTML/查 App）。
    if (_toolsEnabled) {
      _pendingSteps.clear();
      try {
        final history = <agent.ChatTurn>[
          for (final record in _conversation.messages
              .where((m) => m.role == 'user' || m.role == 'assistant')
              .toList()
              .take(_conversation.messages.length - 1))
            agent.ChatTurn(isUser: record.role == 'user', text: record.text),
        ];
        final configs = context.read<ApiProvider>().allApiConfigs;
        final result = await agent.AgentRunner.run(
          userPrompt: text,
          configs: configs,
          // 用本对话自己的配置（不看全局 AI 设置）。
          cloudConfig: widget.apiConfig,
          history: history.length > 6
              ? history.sublist(history.length - 6)
              : history,
          onStep: (step) {
            if (mounted) setState(() => _pendingSteps.add(step));
          },
        );
        if (!mounted || requestId != _requestId) return;
        setState(() {
          _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: result.text.isEmpty
                ? (result.error ?? '（没有返回内容）')
                : result.text,
            // 工具模式也把思考过程留下来（之前完全不收集，所以"看不到思考"）。
            thinking: result.thinking.isEmpty ? null : result.thinking,
            toolSteps: [
              for (final step in result.steps)
                '${step.tool}(${step.argsLabel})：${_shorten(step.result)}',
            ],
          ));
          _isGenerating = false;
        });
        await _store.save(_conversation);
      } catch (e) {
        if (mounted && requestId == _requestId) {
          setState(() {
            _isGenerating = false;
            _conversation.messages.add(ChatMessageRecord(
                role: 'assistant', text: '工具调用失败：$e'));
          });
        }
      }
      _scrollToBottom();
      return;
    }

    final buffer = StringBuffer();
    final thinking = StringBuffer();
    String? errorText;

    try {
      // 记忆：用户说"记住…"自动入库；开了记忆插件则注入相关记忆。
      if (ToolRegistry.isCategoryEnabled('memory')) {
        final explicit = MemoryStore.extractExplicitMemory(text);
        if (explicit != null) await MemoryStore.save(explicit);
      }
      final memorySection = ToolRegistry.isCategoryEnabled('memory')
          ? await MemoryStore.buildPromptSection(text)
          : '';
      final body = <String, dynamic>{
        'messages': _buildMessages(memorySection: memorySection),
        'temperature': _conversation.settings.temp,
        'max_tokens': _conversation.settings.maxTokens,
      };
      await for (final event in _apiService.sendRequestStream(
        apiConfig: widget.apiConfig,
        model: _selectedModel,
        requestBody: body,
      )) {
        if (!mounted || requestId != _requestId) return;
        if (_stopRequested) break;
        if (event.reasoning != null && event.reasoning!.isNotEmpty) {
          thinking.write(event.reasoning);
        }
        if (event.delta != null && event.delta!.isNotEmpty) {
          buffer.write(event.delta);
        }
        setState(() {
          _streamText = buffer.toString();
          _streamThinking = thinking.toString();
        });
        _scrollToBottom();
      }
    } on ApiException catch (e) {
      errorText = 'HTTP ${e.statusCode}: ${_shorten(e.body)}';
    } catch (e) {
      errorText = e.toString();
    }

    if (!mounted || requestId != _requestId) return;
    final stopped = _stopRequested;
    setState(() {
      if (errorText != null) {
        _conversation.messages.add(ChatMessageRecord(
            role: 'assistant', text: '请求失败：$errorText'));
      } else if (buffer.isEmpty && thinking.isEmpty) {
        _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: stopped ? '（已停止生成）' : '（模型没有返回内容）'));
      } else {
        _conversation.messages.add(ChatMessageRecord(
          role: 'assistant',
          text: stopped ? '$buffer（已停止）' : buffer.toString(),
          thinking: thinking.isEmpty ? null : thinking.toString(),
        ));
      }
      _streamText = '';
      _streamThinking = '';
      _isGenerating = false;
      _stopRequested = false;
    });
    await _store.save(_conversation);
    _scrollToBottom();
  }

  String _shorten(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  /// 构造发给云端的 messages（系统提示词 + 长期记忆 + 历史）。
  List<Map<String, dynamic>> _buildMessages({String memorySection = ''}) {
    final messages = <Map<String, dynamic>>[];
    final systemText = [
      if (_conversation.settings.systemPrompt.trim().isNotEmpty)
        _conversation.settings.systemPrompt.trim(),
      if (memorySection.isNotEmpty) memorySection,
    ].join('\n\n');
    if (systemText.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemText});
    }
    for (final record in _conversation.messages) {
      if (record.role == 'assistant' && record.text.startsWith('请求失败：')) {
        continue; // 失败提示不进上下文。
      }
      messages.add({'role': record.role, 'content': record.text});
    }
    return messages;
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final settings = _conversation.settings;
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
                    if (widget.apiConfig.models.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedModel.isEmpty
                            ? null
                            : _selectedModel,
                        decoration: const InputDecoration(
                          labelText: '模型',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: widget.apiConfig.models
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() {});
                          setState(() => _selectedModel = value);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_toolsEnabled ? '使用工具（插件）：已开启' : '使用工具（插件）'),
                      subtitle: const Text('联网搜索 / 新闻 / 抓网页 / 算术 / HTML / 待办 / 找模型…'
                          '（与右上角插件面板同一个开关）'),
                      value: _toolsEnabled,
                      onChanged: (v) {
                        // 先刷新面板本身，再通知页面（否则点了看不到变化）。
                        setSheetState(() {});
                        setState(() => _toolsEnabled = v);
                        unawaited(ToolRegistry.setMasterEnabled(v));
                      },
                    ),
                    _sliderRow(
                      label: '温度（越高越随机）',
                      value: settings.temp,
                      min: 0,
                      max: 2,
                      display: settings.temp.toStringAsFixed(2),
                      onChanged: (v) => update(settings.copyWith(temp: v)),
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
                    Text('参数按对话保存；对话记录保存在本机。',
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
        builder: (context) => ApiChatScreen(apiConfig: widget.apiConfig),
      ),
    );
  }

  void _openConversationList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConversationListScreen(
          modelPath: ApiChatScreen.conversationKeyFor(widget.apiConfig.id),
          modelName: widget.apiConfig.name,
          apiConfig: widget.apiConfig,
        ),
      ),
    ).then((_) {
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
    _requestId++; // 作废在途流。
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // _conversation 异步初始化：就绪前回退到配置名，避免
            // late 字段未初始化抛错（整页渲染成错误占位）。
            Text(_ready ? _conversation.title : widget.apiConfig.name,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(_selectedModel.isEmpty ? '未选择模型' : _selectedModel,
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
              visionAvailable: false,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '生成参数',
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _selectedModel.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '这个配置还没有模型。先点右上角"编辑"补上模型列表，再回来对话。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary),
                    ),
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
                                  Icon(Icons.forum_outlined,
                                      size: 48, color: secondary),
                                  const SizedBox(height: 12),
                                  Text('与 ${widget.apiConfig.name} 开始对话',
                                      style: TextStyle(color: secondary)),
                                  const SizedBox(height: 4),
                                  Text('多轮对话会带上上下文，记录保存在本机',
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
                                if (index >=
                                    _conversation.messages.length) {
                                  return _buildStreamingBubble(isDark);
                                }
                                return _buildBubble(
                                    index,
                                    _conversation.messages[index],
                                    isDark);
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
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
                                    ? () => setState(
                                        () => _stopRequested = true)
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
            if (_streamThinking.isNotEmpty)
              _thinkingPanel(_streamThinking, -1, isDark),
            Text(_streamText.isEmpty ? '…' : _streamText),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(int index, ChatMessageRecord record, bool isDark) {
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
            if (!isUser && record.toolSteps.isNotEmpty)
              _thinkingPanel(record.toolSteps.join('\n\n'), index + 100000,
                  isDark, title: '查看工具调用（${record.toolSteps.length} 步）'),
            if (!isUser &&
                record.thinking != null &&
                record.thinking!.isNotEmpty)
              _thinkingPanel(record.thinking!, index, isDark),
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

  /// 思考过程（推理模型）：默认折叠，点击展开。
  Widget _thinkingPanel(String thinking, int index, bool isDark,
      {String? title}) {
    final expanded = _expandedThinking.contains(index);
    final color = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
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
              child: SelectableText(thinking,
                  style: TextStyle(fontSize: 12, height: 1.4, color: color)),
            ),
        ],
      ),
    );
  }
}
