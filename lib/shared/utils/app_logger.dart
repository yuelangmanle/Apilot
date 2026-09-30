import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 全局错误兜底与本地滚动日志。
///
/// release 下未捕获异常会被静默吞掉、无法感知线上问题；这里把框架异常、
/// 异步异常与损坏的 widget 构建统一写入本地日志文件（保留最近 5 个）。
class AppLogger {
  AppLogger._();

  static const int _maxFiles = 5;
  static File? _logFile;

  static Future<Directory?> _logDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String level, String message) async {
    try {
      final dir = await _logDir();
      if (dir == null) return;
      final now = DateTime.now();
      final dateTag =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _logFile ??= File('${dir.path}/apilot-$dateTag.log');
      final line =
          '[${now.toIso8601String()}][$level] '
          '${message.split('\n').take(30).join('\n')}\n';
      await _logFile!.writeAsString(line, mode: FileMode.append);
      await _rotateIfNeeded(dir, dateTag);
    } catch (_) {
      // 日志自身失败绝不二次抛出。
    }
  }

  static Future<void> _rotateIfNeeded(
      Directory dir, String currentDateTag) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final file in files.skip(_maxFiles)) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      if (_logFile != null && !_logFile!.path.contains(currentDateTag)) {
        _logFile = null;
      }
    } catch (_) {}
  }

  /// 在 main() 里安装三大兜底：框架异常 / 异步异常 / 构建异常。
  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(write('FLUTTER', details.exceptionAsString()));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(write('UNCAUGHT', '$error'));
      return true;
    };
  }

  static Widget errorWidgetBuilder(FlutterErrorDetails details) {
    unawaited(write('WIDGET', details.exceptionAsString()));
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF1E1E1E)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '本区域渲染出错，已记录日志。',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
