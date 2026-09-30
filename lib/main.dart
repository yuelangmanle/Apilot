import 'dart:async';

import 'package:flutter/material.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiManagerApp.bootstrap();
  runApp(const ApiManagerApp());
  // 回收站过期清理不阻塞首帧：开屏后异步执行。
  unawaited(ApiManagerApp.purgeRecycleBinAfterStartup());
}
