import 'dart:async';

import 'package:flutter/services.dart';

/// 剪贴板隐私：复制 API Key 后延迟清空剪贴板，避免 Key 长时间
/// 留在系统剪贴板里被其他 App/输入法读取。
class ClipboardPrivacy {
  ClipboardPrivacy._();

  static const Duration autoClearAfter = Duration(seconds: 60);
  static Timer? _timer;
  static String? _pendingValue;

  /// 复制敏感内容并安排自动清除。若内容在到时前被替换，则不清除。
  static void copySensitive(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _pendingValue = value;
    _timer?.cancel();
    _timer = Timer(autoClearAfter, () async {
      final expected = _pendingValue;
      _pendingValue = null;
      if (expected == null || expected.isEmpty) return;
      try {
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == expected) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        // 读取剪贴板失败时保持现状，不打扰用户。
      }
    });
  }
}
