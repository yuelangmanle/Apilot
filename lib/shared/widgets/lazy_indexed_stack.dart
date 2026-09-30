import 'package:flutter/material.dart';

/// 懒加载保活 IndexedStack：
/// - 子项在**首次被选中**时才构建（避免启动时全量挂载，
///   也让依赖平台通道的页面不在不支持的平台崩溃）；
/// - 构建后通过 Visibility.maintain 保活，切换零重建，
///   滚动位置/搜索词/多选状态全部保留。
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Alignment alignment;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late List<bool> _activated =
      List<bool>.generate(widget.children.length, (i) => i == widget.index);

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (widget.index < _activated.length) {
        _activated[widget.index] = true;
      }
    }
    if (widget.children.length != _activated.length) {
      _activated =
          List<bool>.generate(widget.children.length, (i) => i == widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      alignment: widget.alignment,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _activated[i]
              ? Visibility.maintain(
                  visible: i == widget.index,
                  child: widget.children[i],
                )
              : const SizedBox.shrink(),
      ],
    );
  }
}
