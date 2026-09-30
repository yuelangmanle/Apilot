import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'shared/utils/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.install();
  ErrorWidget.builder = (details) {
    AppLogger.write('WIDGET', details.exceptionAsString());
    return const ColoredBox(
      color: Color(0xFF1E1E1E),
      child: Center(
        child: Text('本区域渲染出错，已记录日志。',
            style: TextStyle(color: Colors.white70)),
      ),
    );
  };
  await ApiManagerApp.bootstrap();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await _initDesktopWindow();
  }
  runApp(const ApiManagerApp());
  // 不阻塞首帧的启动后任务：回收站清理与价格表更新。
  unawaited(ApiManagerApp.purgeRecycleBinAfterStartup());
  unawaited(ApiManagerApp.refreshPriceTableAfterStartup());
}

/// 桌面端：最小尺寸约束 + 恢复上次窗口几何。
Future<void> _initDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    const minSize = Size(480, 620);
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('window_width') ?? 1100;
    final height = prefs.getDouble('window_height') ?? 760;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(
          width.clamp(minSize.width, 3840),
          height.clamp(minSize.height, 2160),
        ),
        minimumSize: minSize,
        title: 'Apilot',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (e) {
    debugPrint('[Window] 桌面窗口初始化失败: $e');
  }
}


