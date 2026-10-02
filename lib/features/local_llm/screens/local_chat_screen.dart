import 'package:flutter/material.dart';
import 'package:llamadart/llamadart.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../shared/theme/color_scheme.dart';

/// 本地对话：与已下载的本地模型进行多轮对话。
class LocalChatScreen extends StatefulWidget {
  final String modelPath;
  final String modelName;

  const LocalChatScreen({
    super.key,
    required this.modelPath,
    required this.modelName,
  });

  @override
  State<LocalChatScreen> createState() => _LocalChatScreenState();
}

class _ChatTurn {
  final String role;
  final String text;

  const _ChatTurn(this.role, this.text);
}

class _LocalChatScreenState extends State<LocalChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatTurn> _turns = [];
  bool _isGenerating = false;
  String _streamBuffer = '';
  bool _initialized = false;

  late final LocalLlmEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = LocalLlmEngine();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _engine.loadModel(widget.modelPath);
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模型加载失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;
    _controller.clear();
    setState(() {
      _turns.add(_ChatTurn('user', text));
      _isGenerating = true;
      _streamBuffer = '';
    });
    _scrollToBottom();

    try {
      final messages = <LlamaChatMessage>[
        for (final turn in _turns)
          LlamaChatMessage.fromText(
            role: turn.role == 'user'
                ? LlamaChatRole.user
                : LlamaChatRole.assistant,
            text: turn.text,
          ),
      ];

      final buffer = StringBuffer();
      await for (final delta
          in _engine.generateStream(messages, maxTokens: 2048)) {
        if (!mounted) return;
        buffer.write(delta);
        setState(() => _streamBuffer = buffer.toString());
        _scrollToBottom();
      }

      if (mounted) {
        setState(() {
          _turns.add(_ChatTurn('assistant', buffer.toString()));
          _streamBuffer = '';
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _turns.add(_ChatTurn('assistant', '生成失败: $e'));
        });
      }
    }
    _scrollToBottom();
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
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.modelName, style: const TextStyle(fontSize: 16)),
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _turns.isEmpty
                      ? Center(
                          child: Text('输入消息开始对话',
                              style: TextStyle(color: secondary)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _turns.length +
                              (_isGenerating ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _turns.length) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.78),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurface
                                        : AppColors.background,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: Text(_streamBuffer.isEmpty
                                      ? '…'
                                      : _streamBuffer),
                                ),
                              );
                            }
                            final turn = _turns[index];
                            return Align(
                              alignment: turn.role == 'user'
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.78),
                                decoration: BoxDecoration(
                                  color: turn.role == 'user'
                                      ? AppColors.primary
                                      : (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.background),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: SelectableText(
                                  turn.text,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: turn.role == 'user'
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkTextPrimary
                                            : AppColors.textPrimary),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary,
                          child: IconButton(
                            icon: const Icon(Icons.send,
                                color: Colors.white, size: 20),
                            onPressed: _isGenerating ? null : _send,
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
}
