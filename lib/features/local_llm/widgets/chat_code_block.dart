import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/theme/color_scheme.dart';
import '../screens/html_editor_screen.dart';

/// 把助手回复里的 ``` 代码块渲染成"卡片"：可复制 / 运行预览 / 存到草稿。
///
/// 这是"AI 写的 HTML 就是能在聊天里直接用"的关键：不用再让用户
/// 手抄代码去别处粘贴。
class ChatCodeBlock extends StatelessWidget {
  final String language;
  final String code;

  const ChatCodeBlock({super.key, required this.language, required this.code});

  bool get _isHtml => language.toLowerCase() == 'html' ||
      code.trimLeft().toLowerCase().startsWith('<!doctype html') ||
      code.trimLeft().toLowerCase().startsWith('<html');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final preview = code.length > 400
        ? '${code.substring(0, 400)}\n…（共 ${code.length} 字符，点"预览"查看完整页面）'
        : code;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：语言 + 操作
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 0),
            child: Row(
              children: [
                Icon(_isHtml ? Icons.code : Icons.terminal,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  _isHtml ? 'HTML 代码' : (language.isEmpty ? '代码' : language),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('代码已复制'),
                        duration: Duration(seconds: 1)));
                  },
                ),
                if (_isHtml)
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    tooltip: '运行预览',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HtmlEditorScreen(
                          initialTitle: 'AI 生成 ${DateTime.now().month}-'
                              '${DateTime.now().day}',
                          initialHtml: code,
                          startInPreview: true,
                        ),
                      ),
                    ),
                  ),
                if (_isHtml)
                  IconButton(
                    icon: const Icon(Icons.save_alt, size: 18),
                    tooltip: '存到草稿（设置 → 工具箱 → HTML 编辑器）',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _saveDraft(context),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              preview,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11.5, height: 1.45),
            ),
          ),
          if (_isHtml)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text('提示：点播放按钮可全屏预览（含轻量渲染），满意后存成草稿再导出。',
                  style: TextStyle(fontSize: 10, color: secondary)),
            ),
        ],
      ),
    );
  }

  Future<void> _saveDraft(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'snippets'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final name = 'AI生成_${DateTime.now().millisecondsSinceEpoch}';
      final file = File(p.join(dir.path, '$name.html'));
      await file.writeAsString(code, flush: true);
      messenger.showSnackBar(const SnackBar(
          content: Text('已存到草稿（设置 → 工具箱 → HTML 编辑器）'),
          backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('保存失败：$e'), backgroundColor: AppColors.error));
    }
  }
}

/// 一段消息内容：纯文本或代码块。
class MessageSegment {
  final bool isCode;
  final String text;
  final String language;

  const MessageSegment.text(this.text)
      : isCode = false,
        language = '';
  const MessageSegment.code(this.text, this.language) : isCode = true;

  /// 解析 ``` 围栏（支持 ```html 这类语言标注）。
  static List<MessageSegment> parse(String content) {
    final segments = <MessageSegment>[];
    final pattern = RegExp(r'```([a-zA-Z0-9_+-]*)\n?([\s\S]*?)(?:```|$)');
    var last = 0;
    for (final match in pattern.allMatches(content)) {
      if (match.start > last) {
        final text = content.substring(last, match.start).trim();
        if (text.isNotEmpty) segments.add(MessageSegment.text(text));
      }
      final language = (match.group(1) ?? '').trim();
      final code = (match.group(2) ?? '').trimRight();
      if (code.trim().isNotEmpty) {
        segments.add(MessageSegment.code(code, language));
      }
      last = match.end;
    }
    if (last < content.length) {
      final text = content.substring(last).trim();
      if (text.isNotEmpty) segments.add(MessageSegment.text(text));
    }
    if (segments.isEmpty) segments.add(MessageSegment.text(content));
    return segments;
  }
}

/// 消息正文：文本段按原样显示（保留换行），代码段落成 [ChatCodeBlock]。
class ChatMessageBody extends StatelessWidget {
  final String text;
  final bool isUser;
  final Color textColor;

  const ChatMessageBody({
    super.key,
    required this.text,
    required this.isUser,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final segments = MessageSegment.parse(text);
    if (segments.length == 1 && !segments.first.isCode) {
      return SelectableText(text,
          style: TextStyle(fontSize: 14, height: 1.5, color: textColor));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          segment.isCode
              ? ChatCodeBlock(
                  language: segment.language, code: segment.text)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(segment.text,
                      style: TextStyle(
                          fontSize: 14, height: 1.5, color: textColor)),
                ),
      ],
    );
  }
}
