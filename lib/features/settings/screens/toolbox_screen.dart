import 'package:flutter/material.dart';

import '../../../core/services/ai/memory_store.dart';
import '../../../core/services/ai/tool_registry.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../local_llm/screens/html_editor_screen.dart';

/// 工具箱：内置 AI 插件一览 + HTML 编辑器入口。
///
/// 让用户明确知道"AI 能替我做什么"（联网搜索、抓网页、算术、存 HTML、
/// 查 App 数据），以及这些工具在对话里怎么开、安全边界在哪。
class ToolboxScreen extends StatelessWidget {
  const ToolboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final tools = ToolRegistry.tools;

    return Scaffold(
      appBar: AppBar(title: const Text('工具箱')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.code, color: AppColors.primary),
              title: const Text('HTML 编辑器'),
              subtitle: const Text('写/改/预览/导出 HTML；AI 生成的页面也会存到这里'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HtmlEditorScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('内置插件（对话里可开启）',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                    '在任意对话页右上角点亮"插件"图标（或参数面板里打开'
                    '"使用工具"），AI 就能调用下面的工具；'
                    '本地模型与云端模型用的是同一套机制。',
                    style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
                  ),
                  const Divider(height: 20),
                  if (tools.isEmpty)
                    Text('工具未注册（App 启动时会注册）',
                        style: TextStyle(fontSize: 12, color: secondary))
                  else
                    for (final tool in tools)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.build_circle_outlined,
                                    size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(tool.name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace')),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(tool.description,
                                style: TextStyle(
                                    fontSize: 12, color: secondary)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('长期记忆',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    'AI 记下的用户事实（对话里会自动带上相关的几条）。'
                    '可以逐条删除；关掉"长期记忆"插件后不再记录也不再注入。',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<MemoryEntry>>(
                    future: MemoryStore.all(),
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? const <MemoryEntry>[];
                      if (entries.isEmpty) {
                        return Text('还没有记忆',
                            style: TextStyle(fontSize: 12, color: secondary));
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in entries.take(20))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(entry.text,
                                  style: const TextStyle(fontSize: 12)),
                              subtitle: Text(
                                '${entry.createdAt.year}-'
                                '${entry.createdAt.month.toString().padLeft(2, '0')}-'
                                '${entry.createdAt.day.toString().padLeft(2, '0')}'
                                '${entry.tags.isEmpty ? '' : ' · ${entry.tags.join('、')}'}',
                                style: TextStyle(fontSize: 11, color: secondary),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  await MemoryStore.delete(entry.id);
                                  if (context.mounted) {
                                    (context as Element).markNeedsBuild();
                                  }
                                },
                              ),
                            ),
                          if (entries.length > 20)
                            Text('（共 ${entries.length} 条，只显示最近 20 条）',
                                style: TextStyle(fontSize: 11, color: secondary)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('安全边界',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                    '· 联网工具只访问公网地址：本机、局域网与保留地址一律拒绝；\n'
                    '· App 数据查询是只读的（列出方案、用量），不会修改或删除任何配置；\n'
                    '· 需要打开页面时会跳转到对应界面，写操作始终由你确认；\n'
                    '· 工具的每一步调用过程都会显示在对话气泡里（可折叠查看）。',
                    style: TextStyle(fontSize: 12, height: 1.6, color: secondary),
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
