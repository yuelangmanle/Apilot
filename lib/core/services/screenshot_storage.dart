import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ScreenshotStorage {
  ScreenshotStorage._();

  static const MethodChannel _channel =
      MethodChannel('com.apilot/screenshot_storage');
  static const String _temporaryFolder = 'apilot_agent_screenshots';
  static const String _temporaryPrefix = 'agent_screenshot_';

  static Future<String> saveToDownloads(Uint8List bytes) async {
    final fileName = 'Apilot_${DateTime.now().millisecondsSinceEpoch}.png';
    if (Platform.isAndroid) {
      final location = await _channel.invokeMethod<String>(
        'saveToDownloads',
        {'name': fileName, 'bytes': bytes},
      );
      if (location == null || location.isEmpty) {
        throw const FileSystemException('系统未返回截图保存位置');
      }
      return location;
    }

    final directory = await getDownloadsDirectory();
    if (directory == null) {
      throw const FileSystemException('无法访问系统下载目录');
    }
    final targetDirectory =
        Directory(p.join(directory.path, 'Apilot', 'Screenshots'));
    await targetDirectory.create(recursive: true);
    final file = File(p.join(targetDirectory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> saveTemporaryForModel(Uint8List bytes) async {
    final directory = await _temporaryDirectory();
    await directory.create(recursive: true);
    final file = File(p.join(
      directory.path,
      '$_temporaryPrefix${DateTime.now().microsecondsSinceEpoch}.png',
    ));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> deleteTemporary(String path) async {
    final directory = await _temporaryDirectory();
    final normalizedDirectory = p.normalize(directory.path);
    final normalizedPath = p.normalize(path);
    if (!p.isWithin(normalizedDirectory, normalizedPath) ||
        !p.basename(normalizedPath).startsWith(_temporaryPrefix)) {
      return;
    }
    try {
      final file = File(normalizedPath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[ScreenshotStorage] 临时截图清理失败: $error');
    }
  }

  static Future<void> cleanupStaleTemporaryFiles({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final directory = await _temporaryDirectory();
      if (!await directory.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entity in directory.list()) {
        if (entity is! File ||
            !p.basename(entity.path).startsWith(_temporaryPrefix)) {
          continue;
        }
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('[ScreenshotStorage] 清理旧截图失败: $error');
    }
  }

  static Future<Directory> _temporaryDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, _temporaryFolder));
  }
}
