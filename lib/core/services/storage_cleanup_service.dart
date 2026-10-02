import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_llm/model_download_service.dart';

/// 一类可清理/可统计的存储项。
class CleanupCategory {
  final String key;
  final String title;
  final String description;
  final int itemCount;
  final int bytes;

  /// 默认是否勾选清理（已下载模型永远 false：只能手动逐个删除）。
  final bool defaultSelected;
  final bool deletable;

  const CleanupCategory({
    required this.key,
    required this.title,
    required this.description,
    required this.itemCount,
    required this.bytes,
    required this.defaultSelected,
    this.deletable = true,
  });

  String get sizeLabel => StorageCleanupService.formatBytes(bytes);
}

/// 存储扫描结果。
class StorageReport {
  final List<CleanupCategory> categories;
  const StorageReport(this.categories);

  int get totalBytes =>
      categories.fold<int>(0, (sum, c) => sum + c.bytes);

  /// 可清理（勾选项）的字节数。
  int get reclaimableBytes => categories
      .where((c) => c.deletable && c.defaultSelected)
      .fold<int>(0, (sum, c) => sum + c.bytes);
}

/// 存储统计与清理：把"垃圾"和"资产"分开列清楚，
/// 已下载的模型默认不动，只能由用户显式选择删除。
class StorageCleanupService {
  StorageCleanupService._();

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static Future<int> _dirBytes(Directory dir) async {
    var total = 0;
    try {
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 扫描存储：区分"未完成下载/孤儿元数据/日志/临时文件"与"已下载模型"。
  static Future<StorageReport> scan() async {
    final categories = <CleanupCategory>[];

    // 1) 未完成的下载（.part）与其元数据（.meta.json）
    final partials = await ModelDownloadService.listPartialDownloads();
    var partialBytes = 0;
    var orphanBytes = 0;
    var orphanCount = 0;
    try {
      final modelsDir = await ModelDownloadService.modelsDir();
      for (final file in modelsDir.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        if (name.endsWith('.part')) {
          try {
            partialBytes += file.lengthSync();
          } catch (_) {}
        } else if (name.endsWith('.meta.json')) {
          // 没有对应 .part / 正式文件的 sidecar 即为孤儿。
          final base = file.path.substring(0, file.path.length - '.meta.json'.length);
          if (!File('$base.part').existsSync() && !File(base).existsSync()) {
            orphanCount++;
            try {
              orphanBytes += file.lengthSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    categories.add(CleanupCategory(
      key: 'partials',
      title: '未完成的下载',
      description: '下载中断留下的临时文件（.part）。删除后需要重新下载。',
      itemCount: partials.length,
      bytes: partialBytes,
      defaultSelected: false,
      deletable: partials.isNotEmpty,
    ));
    categories.add(CleanupCategory(
      key: 'orphanMeta',
      title: '残留的下载记录',
      description: '已无对应文件的下载来源记录（.meta.json），删除不影响模型。',
      itemCount: orphanCount,
      bytes: orphanBytes,
      defaultSelected: true,
      deletable: orphanCount > 0,
    ));

    // 2) 日志
    var logCount = 0;
    var logBytes = 0;
    try {
      final support = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(support.path, 'logs'));
      if (logsDir.existsSync()) {
        for (final file in logsDir.listSync().whereType<File>()) {
          if (!file.path.endsWith('.log')) continue;
          logCount++;
          try {
            logBytes += file.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    categories.add(CleanupCategory(
      key: 'logs',
      title: '运行日志',
      description: '应用错误与运行日志（排查问题用）。清理后会重新开始记录。',
      itemCount: logCount,
      bytes: logBytes,
      defaultSelected: true,
      deletable: logCount > 0,
    ));

    // 3) 临时目录
    var tempBytes = 0;
    var tempCount = 0;
    try {
      final temp = await getTemporaryDirectory();
      if (temp.existsSync()) {
        for (final entity in temp.listSync(recursive: true)) {
          if (entity is File) {
            tempCount++;
            try {
              tempBytes += entity.lengthSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    categories.add(CleanupCategory(
      key: 'temp',
      title: '临时文件',
      description: '系统缓存目录内容（下载中转、预览缓存等）。',
      itemCount: tempCount,
      bytes: tempBytes,
      defaultSelected: true,
      deletable: tempCount > 0,
    ));

    // 4) 已下载模型（资产，默认不清理）
    var modelCount = 0;
    var modelBytes = 0;
    try {
      final files = await ModelDownloadService.listDownloadedModels();
      modelCount = files.length;
      for (final file in files) {
        try {
          modelBytes += file.lengthSync();
        } catch (_) {}
      }
    } catch (_) {}
    categories.add(CleanupCategory(
      key: 'models',
      title: '已下载模型',
      description: '可离线对话的模型文件。默认不清理——删除后需要重新下载。',
      itemCount: modelCount,
      bytes: modelBytes,
      defaultSelected: false,
      deletable: false,
    ));

    return StorageReport(categories);
  }

  /// 按选择清理。返回释放的字节数（估算）。
  /// 已下载模型不在可清理范围内（[CleanupCategory.deletable] = false）。
  static Future<int> clean(Set<String> selectedKeys) async {
    var freed = 0;

    if (selectedKeys.contains('partials')) {
      try {
        final modelsDir = await ModelDownloadService.modelsDir();
        for (final file in modelsDir.listSync().whereType<File>()) {
          if (!file.path.endsWith('.part')) continue;
          try {
            freed += file.lengthSync();
            await file.delete();
            // 对应的 sidecar 一并清掉，避免留下孤儿记录。
            final base = file.path.substring(0, file.path.length - 5);
            final sidecar = File('$base.meta.json');
            if (sidecar.existsSync()) await sidecar.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (selectedKeys.contains('orphanMeta')) {
      try {
        final modelsDir = await ModelDownloadService.modelsDir();
        for (final file in modelsDir.listSync().whereType<File>()) {
          if (!file.path.endsWith('.meta.json')) continue;
          final base =
              file.path.substring(0, file.path.length - '.meta.json'.length);
          if (File('$base.part').existsSync() || File(base).existsSync()) {
            continue;
          }
          try {
            freed += file.lengthSync();
            await file.delete();
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (selectedKeys.contains('logs')) {
      try {
        final support = await getApplicationSupportDirectory();
        final logsDir = Directory(p.join(support.path, 'logs'));
        if (logsDir.existsSync()) {
          for (final file in logsDir.listSync().whereType<File>()) {
            if (!file.path.endsWith('.log')) continue;
            try {
              freed += file.lengthSync();
              await file.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (selectedKeys.contains('temp')) {
      try {
        final temp = await getTemporaryDirectory();
        if (temp.existsSync()) {
          for (final entity in temp.listSync()) {
            try {
              if (entity is File) {
                freed += entity.lengthSync();
                await entity.delete();
              } else if (entity is Directory) {
                freed += await _dirBytes(entity);
                await entity.delete(recursive: true);
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    debugPrint('[Cleanup] 释放约 $freed 字节');
    return freed;
  }
}
