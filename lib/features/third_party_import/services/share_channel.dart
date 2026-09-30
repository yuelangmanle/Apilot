import 'dart:async';

import 'package:flutter/services.dart';

/// Android 系统分享目标通道：其他 App 通过系统分享把文本交给 Apilot
/// 识别。启动冷路径经 getInitialShareText 拉取，热路径经 onShareReceived 推送。
class ShareChannel {
  ShareChannel._();

  static const MethodChannel _channel = MethodChannel('com.apilot/share');

  static bool _initialized = false;
  static final StreamController<String> _shareTextController =
      StreamController<String>.broadcast();

  static Stream<String> get shareTextStream => _shareTextController.stream;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived' && call.arguments is String) {
        _shareTextController.add(call.arguments as String);
      }
      return null;
    });
  }

  /// 冷启动拉取初始分享文本；无则返回 null。
  static Future<String?> getInitialShareText() async {
    try {
      return await _channel.invokeMethod<String>('getInitialShareText');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
