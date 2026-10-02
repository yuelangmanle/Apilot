import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模型存储位置设置。
///
/// 默认放应用私有目录；也可以切到**公共下载目录**（Download/Apilot），
/// 这样在系统文件管理器里能直接看到模型文件（安卓私有目录很难翻）。
/// 桌面端支持自选目录。
class ModelStorageSettings {
  ModelStorageSettings._();

  static const _modeKey = 'model_storage_mode'; // private / public / custom
  static const _customDirKey = 'model_storage_custom_dir';

  static String _mode = 'private';
  static String? _customDir;

  static String get mode => _mode;
  static String? get customDir => _customDir;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = prefs.getString(_modeKey) ?? 'private';
      _customDir = prefs.getString(_customDirKey);
    } catch (e) {
      debugPrint('[Storage] 读取设置失败: $e');
    }
  }

  static Future<void> setMode(String mode, {String? customDir}) async {
    _mode = mode;
    _customDir = customDir ?? _customDir;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, _mode);
      if (_customDir != null) await prefs.setString(_customDirKey, _customDir!);
    } catch (e) {
      debugPrint('[Storage] 保存设置失败: $e');
    }
  }

  /// 安卓公共下载目录（需要"所有文件访问"权限）。
  static String get androidPublicDir => '/storage/emulated/0/Download/Apilot';

  /// 目标目录（不存在则创建）。公共目录权限不足时回退私有目录并说明。
  static Future<(Directory dir, String? warning)> resolveDir() async {
    if (Platform.isAndroid && _mode == 'public') {
      final granted = await Permission.manageExternalStorage.isGranted;
      if (!granted) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          return (
            await _privateDir(),
            '没有"所有文件访问"权限，已继续使用应用私有目录；'
                '要放到 Download/Apilot 请在系统设置里允许本应用访问所有文件'
          );
        }
      }
      final dir = Directory(androidPublicDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return (dir, null);
    }
    if (_mode == 'custom' && _customDir != null && _customDir!.isNotEmpty) {
      final dir = Directory(_customDir!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return (dir, null);
    }
    return (await _privateDir(), null);
  }

  static Future<Directory> _privateDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'models'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 把旧目录里的模型搬到新目录（切换存储位置时用，避免"模型看不见了"）。
  /// 返回 (移动成功数, 失败数)。
  static Future<(int moved, int failed)> moveModels(
      Directory from, Directory to) async {
    var moved = 0;
    var failed = 0;
    if (!from.existsSync() || from.path == to.path) return (0, 0);
    for (final entity in from.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.gguf') && !name.endsWith('.gguf.part')) continue;
      try {
        final target = File(p.join(to.path, name));
        if (target.existsSync()) {
          await entity.delete();
        } else {
          await entity.rename(target.path);
        }
        moved++;
      } catch (e) {
        // 跨分区 rename 会失败：退回复制 + 删除。
        try {
          final bytes = await entity.readAsBytes();
          await File(p.join(to.path, p.basename(entity.path)))
              .writeAsBytes(bytes, flush: true);
          await entity.delete();
          moved++;
        } catch (e2) {
          debugPrint('[Storage] 移动失败 ${entity.path}: $e2');
          failed++;
        }
      }
    }
    return (moved, failed);
  }
}
