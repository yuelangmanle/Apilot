import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/api_config.dart';
import 'package:provider/provider.dart';
import '../../../core/services/ai/agent_runner.dart' as agent;
import '../../../core/services/ai/memory_store.dart';
import '../../../core/services/ai/tool_registry.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/api_protocol_adapter.dart';
import '../../../core/services/ai/chat_attachment_encoder.dart';
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
  final ValueNotifier<int> _streamRevision = ValueNotifier(0);
  String _streamText = '';
  String _streamThinking = '';
  final Set<int> _expandedThinking = {};
  int _requestId = 0;
  bool _toolsEnabled = ToolRegistry.masterEnabled;
  final List<agent.AgentStep> _pendingSteps = [];
  final List<ChatAttachment> _pendingAttachments = [];
  final Set<String> _uploadingAttachmentPaths = {};
  Timer? _scrollTimer;
  Timer? _streamFlushTimer;
  StringBuffer? _liveTextBuffer;
  StringBuffer? _liveThinkingBuffer;
  ApiRequestCancellation? _requestCancellation;

  void _scheduleStreamFlush() {
    if (_streamFlushTimer != null) return;
    _streamFlushTimer = Timer(const Duration(milliseconds: 70), () {
      _streamFlushTimer = null;
      _flushStreamBuffers();
    });
  }

  void _flushStreamBuffers() {
    if (!mounted) return;
    final textBuffer = _liveTextBuffer;
    final thinkingBuffer = _liveThinkingBuffer;
    if (textBuffer != null) _streamText = textBuffer.toString();
    if (thinkingBuffer != null) _streamThinking = thinkingBuffer.toString();
    _streamRevision.value++;
    _scrollToBottom();
  }

  void _flushStreamImmediately() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _flushStreamBuffers();
  }

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
    final attachments = List<ChatAttachment>.from(_pendingAttachments);
    if ((text.isEmpty && attachments.isEmpty) || _isGenerating) return;

    _controller.clear();
    final requestId = ++_requestId;
    final cancellation = ApiRequestCancellation();
    _requestCancellation = cancellation;
    var buffer = StringBuffer();
    final thinking = StringBuffer();
    _liveTextBuffer = buffer;
    _liveThinkingBuffer = thinking;
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
          attachments: attachments,
          // 同上：完整历史，保证前缀稳定（上下文管理负责压缩）。
          history: history,
          onDelta: (delta) {
            if (!mounted || requestId != _requestId) return;
            buffer.write(delta);
            _scheduleStreamFlush();
          },
          onStep: (step) {
            if (!mounted) return;
            buffer = StringBuffer();
            _liveTextBuffer = buffer;
            setState(() {
              _pendingSteps.add(step);
              _streamText = '';
            });
          },
          cancellation: cancellation,
        );
        if (!mounted || requestId != _requestId) return;
        final stopped = _stopRequested || cancellation.isCancelled;
        _flushStreamImmediately();
        setState(() {
          _conversation.messages.add(ChatMessageRecord(
            role: 'assistant',
            text: stopped
                ? (result.text.isEmpty ? '（已停止生成）' : '${result.text}（已停止）')
                : result.error != null
                    ? (result.text.isEmpty
                        ? result.error!
                        : '${result.text}\n\n调用失败：${result.error}')
                    : (result.text.isEmpty ? '（没有返回内容）' : result.text),
            // 工具模式也把思考过程留下来（之前完全不收集，所以"看不到思考"）。
            thinking: result.thinking.isEmpty ? null : result.thinking,
            toolSteps: [
              for (final step in result.steps)
                '${step.tool}(${step.argsLabel})：${_shorten(step.result)}',
            ],
          ));
          _isGenerating = false;
          _stopRequested = false;
        });
        await _store.save(_conversation);
        if (identical(_requestCancellation, cancellation)) {
          _requestCancellation = null;
        }
      } catch (e) {
        _streamFlushTimer?.cancel();
        _streamFlushTimer = null;
        if (mounted && requestId == _requestId) {
          final stopped = _stopRequested || cancellation.isCancelled;
          setState(() {
            _isGenerating = false;
            _conversation.messages.add(ChatMessageRecord(
                role: 'assistant', text: stopped ? '（已停止生成）' : '工具调用失败：$e'));
            _stopRequested = false;
          });
        }
        if (identical(_requestCancellation, cancellation)) {
          _requestCancellation = null;
        }
      }
      _scrollToBottom();
      return;
    }

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
        'messages': await _buildMessages(memorySection: memorySection),
        'temperature': _conversation.settings.temp,
        'max_tokens': _conversation.settings.maxTokens,
      };
      await for (final event in _apiService.sendRequestStream(
        apiConfig: widget.apiConfig,
        model: _selectedModel,
        requestBody: body,
        shouldStop: () => _stopRequested,
        cancellation: cancellation,
      )) {
        if (!mounted || requestId != _requestId) return;
        if (_stopRequested) break;
        if (event.reasoning != null && event.reasoning!.isNotEmpty) {
          thinking.write(event.reasoning);
        }
        if (event.delta != null && event.delta!.isNotEmpty) {
          buffer.write(event.delta);
        }
        if ((event.delta?.isNotEmpty ?? false) ||
            (event.reasoning?.isNotEmpty ?? false)) {
          _scheduleStreamFlush();
        }
      }
    } on ApiException catch (e) {
      errorText = 'HTTP ${e.statusCode}: ${_shorten(e.body)}';
    } catch (e) {
      errorText = e.toString();
    }

    _flushStreamImmediately();
    if (!mounted || requestId != _requestId) return;
    final stopped = _stopRequested;
    setState(() {
      if (stopped && cancellation.isCancelled) {
        _conversation.messages
            .add(const ChatMessageRecord(role: 'assistant', text: '（已停止生成）'));
      } else if (errorText != null) {
        _conversation.messages
            .add(ChatMessageRecord(role: 'assistant', text: '请求失败：$errorText'));
      } else if (buffer.isEmpty && thinking.isEmpty) {
        _conversation.messages.add(ChatMessageRecord(
            role: 'assistant', text: stopped ? '（已停止生成）' : '（模型没有返回内容）'));
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
    if (identical(_requestCancellation, cancellation)) {
      _requestCancellation = null;
    }
  }

  String _shorten(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  /// 构造发给云端的 messages（系统提示词 + 长期记忆 + 历史）。
  Future<List<Map<String, dynamic>>> _buildMessages(
      {String memorySection = ''}) async {
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
      // 工具协议行不进历史：否则云端模型会照着模仿（"回复 current_time"）。
      final cleaned = ToolRegistry.stripCall(record.text).trim();
      if (cleaned.isEmpty && record.attachments.isEmpty) continue;
      messages.add({
        'role': record.role,
        'content': await ChatAttachmentEncoder.encodeUserContent(
          cleaned,
          record.attachments,
        ),
      });
    }
    return messages;
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'txt',
        'md',
        'json',
        'csv',
        'log',
        'yaml',
        'yml',
      ],
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final conversationId = _conversation.id;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final extension = (file.extension ?? '').toLowerCase();
      final type = const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
          ? 'image'
          : 'text';
      try {
        _pendingAttachments.add(await _store.importAttachment(
          conversationId,
          sourcePath: path,
          name: file.name,
          type: type,
        ));
      } catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text('导入 ${file.name} 失败: $error'),
          backgroundColor: AppColors.error,
        ));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _removePendingAttachment(int index) async {
    if (index < 0 || index >= _pendingAttachments.length) return;
    final attachment = _pendingAttachments[index];
    setState(() => _pendingAttachments.removeAt(index));
    await _store.deleteAttachment(attachment.path);
  }

  Future<void> _uploadPendingAttachment(int index) async {
    if (index < 0 || index >= _pendingAttachments.length) return;
    final attachment = _pendingAttachments[index];
    final path = attachment.path;
    if (attachment.remoteFileId?.isNotEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('这个附件已经上传过了'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('这个附件没有可上传的本地副本'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    if (ApiProtocolAdapter.defaultFileUploadEndpoint(
          widget.apiConfig.protocolId,
        ) ==
        null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前协议没有通用 /files 接口，聊天仍可使用内联附件'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    setState(() => _uploadingAttachmentPaths.add(path));
    try {
      final result = await _apiService.uploadFile(
        apiConfig: widget.apiConfig,
        filePath: path,
        purpose: 'assistants',
        fileName: attachment.name,
      );
      final fileId = result.id;
      if (fileId == null || fileId.isEmpty) {
        throw StateError('服务端没有返回 file_id');
      }
      if (!mounted) return;
      final currentIndex = _pendingAttachments.indexWhere(
        (item) => item.path == path,
      );
      if (currentIndex >= 0) {
        setState(() {
          _pendingAttachments[currentIndex] =
              _pendingAttachments[currentIndex].copyWith(remoteFileId: fileId);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已上传 ${attachment.name}，file_id：$fileId'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 4),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('上传 ${attachment.name} 失败：$error'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploadingAttachmentPaths.remove(path));
    }
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
                        initialValue:
                            _selectedModel.isEmpty ? null : _selectedModel,
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

  void _newConversation() {
    final pending = List<ChatAttachment>.from(_pendingAttachments);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ApiChatScreen(apiConfig: widget.apiConfig),
      ),
    );
    for (final attachment in pending) {
      unawaited(_store.deleteAttachment(attachment.path));
    }
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
    if (_scrollTimer?.isActive ?? false) return;
    _scrollTimer = Timer(const Duration(milliseconds: 80), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    for (final attachment in _pendingAttachments) {
      unawaited(_store.deleteAttachment(attachment.path));
    }
    _requestId++; // 作废在途流。
    _requestCancellation?.cancel();
    _requestCancellation = null;
    _scrollTimer?.cancel();
    _streamFlushTimer?.cancel();
    _streamRevision.dispose();
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
                                if (index >= _conversation.messages.length) {
                                  return _buildStreamingBubble(isDark);
                                }
                                return _buildBubble(index,
                                    _conversation.messages[index], isDark);
                              },
                            ),
                    ),
                    if (_pendingAttachments.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (var index = 0;
                                index < _pendingAttachments.length;
                                index++)
                              Tooltip(
                                message: _pendingAttachments[index]
                                            .remoteFileId
                                            ?.isNotEmpty ==
                                        true
                                    ? '已上传：${_pendingAttachments[index].remoteFileId}'
                                    : '点击上传到当前 API 的 /files；不上传也可以以内联附件发送',
                                child: InputChip(
                                  avatar: _uploadingAttachmentPaths.contains(
                                          _pendingAttachments[index].path)
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Icon(
                                          _pendingAttachments[index]
                                                      .remoteFileId
                                                      ?.isNotEmpty ==
                                                  true
                                              ? Icons.cloud_done
                                              : (_pendingAttachments[index]
                                                          .type ==
                                                      'image'
                                                  ? Icons.image
                                                  : Icons.description),
                                          size: 16,
                                        ),
                                  label: Text(
                                    _pendingAttachments[index].name,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: _uploadingAttachmentPaths.contains(
                                          _pendingAttachments[index].path)
                                      ? null
                                      : () => _uploadPendingAttachment(index),
                                  onDeleted: () =>
                                      _removePendingAttachment(index),
                                ),
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
            if (record.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final attachment in record.attachments)
                      Chip(
                        avatar: Icon(
                          attachment.type == 'image'
                              ? Icons.image
                              : Icons.description,
                          size: 14,
                        ),
                        label: Text(attachment.name,
                            style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            if (!isUser && record.toolSteps.isNotEmpty)
              _thinkingPanel(
                  record.toolSteps.join('\n\n'), index + 100000, isDark,
                  title: '查看工具调用（${record.toolSteps.length} 步）'),
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
              child: SelectableText(thinking,
                  style: TextStyle(fontSize: 12, height: 1.4, color: color)),
            ),
        ],
      ),
    );
  }
}
