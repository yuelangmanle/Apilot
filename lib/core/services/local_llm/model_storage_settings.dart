import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _storageChannel =
      MethodChannel('com.apilot/storage_permission');

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
          // 这是特殊应用访问权限，不会出现在普通运行时权限弹窗里。
          // 某些 Android/permission_handler 组合 request() 只返回 denied，
          // 因此主动打开正确的系统设置入口，避免用户在权限管理里找不到。
          if (status.isPermanentlyDenied || status.isRestricted) {
            await openAppSettings();
          }
          return (
            await _privateDir(),
            '没有"所有文件访问"权限，已继续使用应用私有目录；'
                '请在「特殊应用访问权限 → 所有文件访问」里允许 Apilot，'
                '返回后重新选择公共目录'
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

  static Future<bool> openPublicStorageSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _storageChannel
              .invokeMethod<bool>('openAllFilesAccessSettings') ??
          false;
    } catch (e) {
      debugPrint('[Storage] 打开所有文件访问设置失败: $e');
      return openAppSettings();
    }
  }

  static Future<Directory> _privateDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'models'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ── 主模型 ↔ 视觉投影配对 ──────────────────────────────────────
  // 投影文件名（mmproj-F16.gguf）通常与主模型名无关，靠名字猜容易配错；
  // 下载时记录下来最可靠。

  static const _pairKey = 'model_projector_pairs';
  static const _pairGroupKey = 'model_projector_pair_groups';
  static Future<void> _pairMutationTail = Future<void>.value();

  static Future<Map<String, String>> projectorPairs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pairKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// 记录"主模型文件 → 视觉投影文件"的配对。
  static Future<bool> pairProjector(
    String mainFileName,
    String projectorFileName, {
    String? shareGroup,
  }) =>
      _withPairMutation(() async {
        try {
          final pairs = await projectorPairs();
          final groups = await _projectorPairGroups();
          final owners = pairs.entries
              .where((entry) =>
                  entry.value == projectorFileName && entry.key != mainFileName)
              .map((entry) => entry.key)
              .toList();
          final hasForeignOwner = owners.any((owner) =>
              shareGroup == null ||
              shareGroup.isEmpty ||
              groups[owner] != shareGroup);
          if (hasForeignOwner) {
            debugPrint('[Storage] 投影已归属其他模型: $projectorFileName -> '
                '${owners.join(', ')}');
            return false;
          }
          pairs[mainFileName] = projectorFileName;
          if (shareGroup == null || shareGroup.isEmpty) {
            groups.remove(mainFileName);
          } else {
            groups[mainFileName] = shareGroup;
          }
          await _writeProjectorPairs(pairs, groups);
          return true;
        } catch (e) {
          debugPrint('[Storage] 记录投影配对失败: $e');
          return false;
        }
      });

  /// 解除某主模型的投影配对（删除模型/投影时调用，避免界面谎报"已装"）。
  static Future<void> unpairProjector(String mainFileName) =>
      _withPairMutation(() async {
        try {
          final pairs = await projectorPairs();
          final groups = await _projectorPairGroups();
          final removed = pairs.remove(mainFileName);
          groups.remove(mainFileName);
          if (removed != null) await _writeProjectorPairs(pairs, groups);
        } catch (e) {
          debugPrint('[Storage] 解除投影配对失败: $e');
        }
      });

  /// 查主模型对应的投影文件名（没有记录则返回 null）。
  static Future<String?> projectorFor(String mainFileName) async {
    final pairs = await projectorPairs();
    return pairs[mainFileName];
  }

  /// 查视觉投影当前归属的主模型。一个投影只能有一个归属。
  static Future<String?> projectorOwner(String projectorFileName) async {
    final pairs = await projectorPairs();
    for (final entry in pairs.entries) {
      if (entry.value == projectorFileName) return entry.key;
    }
    return null;
  }

  static Future<List<String>> projectorOwners(String projectorFileName) async {
    final pairs = await projectorPairs();
    return pairs.entries
        .where((entry) => entry.value == projectorFileName)
        .map((entry) => entry.key)
        .toList();
  }

  static String scopedProjectorFileName(String group, String fileName) {
    final safeGroup = group
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final prefix = safeGroup.isEmpty
        ? 'model'
        : safeGroup.substring(0, safeGroup.length.clamp(0, 48));
    return '${prefix}__${p.basename(fileName)}';
  }

  /// 删除投影文件前清理所有旧版本可能留下的反向配对记录。
  static Future<void> unpairProjectorFile(String projectorFileName) =>
      _withPairMutation(() async {
        try {
          final pairs = await projectorPairs();
          final groups = await _projectorPairGroups();
          final before = pairs.length;
          pairs.removeWhere((_, value) => value == projectorFileName);
          groups.removeWhere((key, _) => !pairs.containsKey(key));
          if (pairs.length != before) await _writeProjectorPairs(pairs, groups);
        } catch (e) {
          debugPrint('[Storage] 清理投影归属失败: $e');
        }
      });

  static Future<void> _writeProjectorPairs(
    Map<String, String> pairs,
    Map<String, String> groups,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairKey, jsonEncode(pairs));
    await prefs.setString(_pairGroupKey, jsonEncode(groups));
  }

  static Future<T> _withPairMutation<T>(Future<T> Function() mutation) async {
    final previous = _pairMutationTail;
    final release = Completer<void>();
    _pairMutationTail = release.future;
    await previous;
    try {
      return await mutation();
    } finally {
      release.complete();
    }
  }

  static Future<Map<String, String>> _projectorPairGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pairGroupKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded
          .map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return {};
    }
  }

  /// 把旧目录里的模型搬到新目录（切换存储位置时用，避免"模型看不见了"）。
  /// 返回 (移动成功数, 失败数)。
  static Future<(int moved, int failed)> moveModels(
      Directory from, Directory to) async {
    var moved = 0;
    var failed = 0;
    if (!from.existsSync() || from.path == to.path) return (0, 0);
    if (!to.existsSync()) await to.create(recursive: true);
    for (final entity in from.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final isModelArtifact = name.endsWith('.gguf') ||
          name.endsWith('.gguf.part') ||
          name.endsWith('.gguf.meta.json');
      if (!isModelArtifact) continue;
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
          await entity.copy(p.join(to.path, name));
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
