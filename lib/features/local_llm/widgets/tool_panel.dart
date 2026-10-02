import 'package:flutter/material.dart';

import '../../../core/services/ai/tool_registry.dart';
import '../../../shared/theme/color_scheme.dart';

/// 插件面板：总开关 + 每个插件独立开关 + 当前待办清单。
///
/// 设计意图：让用户对"AI 能替我做什么"有逐项控制权——搜索、抓网页、
/// 算术、HTML、待办、截屏、查 App 数据各自可关，关掉的分类在模型侧
/// 直接不出现在工具清单里，也不可能被调用。
Future<void> showToolPanel(
  BuildContext context, {
  required bool toolsEnabled,
  required ValueChanged<bool> onToolsChanged,
  required bool visionAvailable,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final secondary = Theme.of(sheetContext).brightness == Brightness.dark
            ? AppColors.darkTextSecondary
            : AppColors.textSecondary;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 插件',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('关掉的插件不会出现在模型的可用工具里，模型也不会调用它。',
                    style: TextStyle(fontSize: 12, color: secondary)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用工具（总开关）',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('关闭后 AI 只做纯对话',
                      style: TextStyle(fontSize: 12)),
                  value: toolsEnabled,
                  onChanged: (v) {
                    onToolsChanged(v);
                    setSheetState(() {});
                  },
                ),
                const Divider(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final category in ToolRegistry.categories)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(category.label,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              category.id == 'screen' && !visionAvailable
                                  ? '${category.description}（当前模型看不了图，截屏只能留档）'
                                  : category.description,
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                            value: toolsEnabled &&
                                ToolRegistry.isCategoryEnabled(category.id),
                            onChanged: !toolsEnabled
                                ? null
                                : (v) async {
                                    await ToolRegistry.setCategoryEnabled(
                                        category.id, v);
                                    setSheetState(() {});
                                  },
                          ),
                        FutureBuilder<List<String>>(
                          future: ToolRegistry.readTodoList(),
                          builder: (context, snapshot) {
                            final items = snapshot.data ?? const [];
                            if (items.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 16),
                                const Text('当前待办（AI 自己维护）',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                for (final item in items)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('· $item',
                                        style:
                                            const TextStyle(fontSize: 12)),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).then((_) {
    // 面板关闭后，让调用方刷新按钮状态。
    onToolsChanged(toolsEnabled);
  });
}
