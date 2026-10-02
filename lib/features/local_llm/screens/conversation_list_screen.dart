import 'package:flutter/material.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/local_llm/chat_conversation_store.dart';
import '../../../shared/theme/color_scheme.dart';
import 'api_chat_screen.dart';
import 'local_chat_screen.dart';

/// 历史对话列表：继续旧对话，或开启新对话（可选择不同模型）。
///
/// 传入 [apiConfig] 时进入云端对话模式（只显示该配置的对话）。
class ConversationListScreen extends StatefulWidget {
  final String modelPath;
  final String modelName;
  final ApiConfig? apiConfig;

  const ConversationListScreen({
    super.key,
    required this.modelPath,
    required this.modelName,
    this.apiConfig,
  });

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _store = ChatConversationStore();
  List<ChatConversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.list();
    // 云端模式只列该配置的对话；本地模式只列本地模型的对话。
    final filtered = widget.apiConfig != null
        ? list.where((c) => c.modelPath == widget.modelPath).toList()
        : list.where((c) => !c.modelPath.startsWith('cloud:')).toList();
    if (mounted) {
      setState(() {
        _conversations = filtered;
        _loading = false;
      });
    }
  }

  Widget _chatScreenFor(ChatConversation conversation) {
    final apiConfig = widget.apiConfig;
    if (apiConfig != null) {
      return ApiChatScreen(
        apiConfig: apiConfig,
        conversationId: conversation.id,
      );
    }
    return LocalChatScreen(
      modelPath: conversation.modelPath,
      modelName: conversation.modelName,
      conversationId: conversation.id,
    );
  }

  Widget _newChatScreen() {
    final apiConfig = widget.apiConfig;
    if (apiConfig != null) return ApiChatScreen(apiConfig: apiConfig);
    return LocalChatScreen(
      modelPath: widget.modelPath,
      modelName: widget.modelName,
    );
  }

  Future<void> _open(ChatConversation conversation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => _chatScreenFor(conversation)),
    );
    _load();
  }

  Future<void> _newConversation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => _newChatScreen()),
    );
    _load();
  }

  Future<void> _delete(ChatConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除对话？'),
        content: Text('「${conversation.title}」的聊天记录将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(conversation.id);
    _load();
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史对话'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '开启新对话',
            onPressed: _newConversation,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined, size: 48, color: secondary),
                      const SizedBox(height: 12),
                      Text('还没有历史对话', style: TextStyle(color: secondary)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _newConversation,
                        icon: const Icon(Icons.add),
                        label: const Text('开启新对话'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];
                    return Dismissible(
                      key: Key(conversation.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: AppColors.error,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        await _delete(conversation);
                        return false; // 由 _delete 内部刷新列表，避免重复移除动画。
                      },
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          child: const Icon(Icons.chat_bubble_outline,
                              color: AppColors.primary, size: 20),
                        ),
                        title: Text(conversation.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(conversation.preview,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              '${conversation.modelName} · ${_formatTime(conversation.updatedAt)} · ${conversation.messages.length} 条',
                              style:
                                  TextStyle(fontSize: 11, color: secondary),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => _open(conversation),
                        onLongPress: () => _delete(conversation),
                      ),
                    );
                  },
                ),
      floatingActionButton: _conversations.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newConversation,
              icon: const Icon(Icons.add),
              label: const Text('开启新对话'),
            ),
    );
  }
}
