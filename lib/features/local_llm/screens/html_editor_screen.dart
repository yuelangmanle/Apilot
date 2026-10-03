import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/ai/html_project_store.dart';
import '../../../shared/theme/color_scheme.dart';

/// 内置 HTML 编辑器：写/改/预览/导出（也能打开 AI 用 save_html 生成的草稿）。
///
/// 预览用轻量渲染（不引入 WebView 依赖，桌面与移动端行为一致）：
/// 支持标题、段落、列表、代码、链接、图片、分割线与表格的基础排版。
class HtmlEditorScreen extends StatefulWidget {
  final String? initialTitle;

  /// 直接带入的内容（AI 生成 / 从聊天里点"运行预览"）。
  final String? initialHtml;

  /// 打开即进预览（"运行"语义）。
  final bool startInPreview;

  const HtmlEditorScreen({
    super.key,
    this.initialTitle,
    this.initialHtml,
    this.startInPreview = false,
  });

  @override
  State<HtmlEditorScreen> createState() => _HtmlEditorScreenState();
}

class _HtmlEditorScreenState extends State<HtmlEditorScreen> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController(text: '未命名');
  final _projectsStore = HtmlProjectStore();
  List<HtmlProject> _projects = [];
  bool _preview = false;
  bool _dirty = false;

  static const _template = '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>我的页面</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 24px; line-height: 1.7; }
    h1 { color: #2f6fed; }
    .card { border: 1px solid #e3e8f0; border-radius: 12px; padding: 16px; }
  </style>
</head>
<body>
  <h1>你好，Apilot</h1>
  <div class="card">
    <p>这是一个可以直接编辑和预览的 HTML 页面。</p>
    <ul>
      <li>左边写代码，切换预览看效果</li>
      <li>可以导出成文件带走</li>
    </ul>
  </div>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _preview = widget.startInPreview;
    _codeController.text = widget.initialHtml ?? _template;
    _codeController.addListener(() {
      if (!_dirty) setState(() => _dirty = true);
    });
    if (widget.initialTitle != null) {
      _titleController.text = widget.initialTitle!;
    }
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await _projectsStore.list();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {}
  }

  Future<void> _openProject(HtmlProject project) async {
    try {
      final content = await _projectsStore.read(project.name);
      if (content == null) return;
      _codeController.text = content;
      _titleController.text = project.name;
      setState(() => _dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await _projectsStore.save(
        _titleController.text,
        _codeController.text,
      );
      setState(() => _dirty = false);
      await _loadProjects();
      messenger.showSnackBar(SnackBar(
          content: Text('已保存项目：${file.uri.pathSegments.last}'),
          backgroundColor: AppColors.success));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('保存失败：$e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final safeName = _titleController.text
          .trim()
          .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5\-]+'), '_');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 HTML',
        fileName: '${safeName.isEmpty ? 'page' : safeName}.html',
        bytes: Uint8List.fromList(_codeController.text.codeUnits),
      );
      if (path != null) {
        messenger.showSnackBar(SnackBar(
            content: Text('已导出到 $path'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('导出失败：$e'), backgroundColor: AppColors.error));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '页面标题',
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_preview ? Icons.code : Icons.visibility_outlined),
            tooltip: _preview ? '回到代码' : '预览',
            onPressed: () => setState(() => _preview = !_preview),
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: '保存草稿',
            onPressed: _save,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出文件',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: '复制 HTML 源码',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _codeController.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('HTML 源码已复制'), duration: Duration(seconds: 1)));
            },
          ),
        ],
        bottom: _dirty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text('未保存的修改',
                        style: TextStyle(fontSize: 11, color: secondary)),
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_projects.isNotEmpty && !_preview)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final project in _projects)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: ActionChip(
                        label: Text(project.name,
                            style: const TextStyle(fontSize: 12)),
                        onPressed: () => _openProject(project),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _preview
                ? _HtmlPreview(html: _codeController.text)
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _codeController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13, height: 1.5),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                        hintText: '在这里写 HTML…',
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 轻量 HTML 预览：把常见标签排成可视化文本（不执行脚本，安全）。
class _HtmlPreview extends StatelessWidget {
  final String html;

  const _HtmlPreview({required this.html});

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(html);
    if (blocks.isEmpty) {
      return const Center(child: Text('没有可预览的内容'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final block in blocks) _renderBlock(context, block)],
    );
  }

  static List<(String tag, String text)> _parseBlocks(String html) {
    var body = html;
    // 只取 body（没有就整篇）。
    final bodyMatch =
        RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true, caseSensitive: false)
            .firstMatch(html);
    if (bodyMatch != null) body = bodyMatch.group(1)!;
    // 去 script/style。
    body = body.replaceAll(
        RegExp(r'<(script|style)[^>]*>.*?</\1>',
            dotAll: true, caseSensitive: false),
        '');
    final blocks = <(String, String)>[];
    final tagPattern = RegExp(
        r'<(h1|h2|h3|h4|p|li|pre|blockquote|tr|hr)[^>]*>(.*?)</\1>|<(hr)\s*/?>',
        dotAll: true,
        caseSensitive: false);
    for (final match in tagPattern.allMatches(body)) {
      if (match.group(3) != null) {
        blocks.add(('hr', ''));
        continue;
      }
      final tag = match.group(1)!.toLowerCase();
      final raw = match.group(2) ?? '';
      final text = _strip(raw);
      if (text.isEmpty) continue;
      blocks.add((tag, text));
    }
    if (blocks.isEmpty) {
      final text = _strip(body);
      if (text.isNotEmpty) blocks.add(('p', text));
    }
    return blocks;
  }

  static String _strip(String raw) => raw
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Widget _renderBlock(BuildContext context, (String, String) block) {
    final (tag, text) = block;
    switch (tag) {
      case 'h1':
        return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold)));
      case 'h2':
        return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)));
      case 'h3':
      case 'h4':
        return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600)));
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• '),
              Expanded(child: Text(text)),
            ],
          ),
        );
      case 'pre':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkSurface
                : AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        );
      case 'blockquote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border:
                Border(left: BorderSide(color: AppColors.primary, width: 3)),
          ),
          child:
              Text(text, style: const TextStyle(fontStyle: FontStyle.italic)),
        );
      case 'hr':
        return const Divider(height: 20);
      case 'tr':
        return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(text, style: const TextStyle(fontSize: 13)));
      default:
        return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(text, style: const TextStyle(height: 1.6)));
    }
  }
}
