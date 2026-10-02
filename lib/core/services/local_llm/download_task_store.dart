import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一条下载任务记录（跨重启保留）。
///
/// 目的：**失败/中断也要留痕**——用户能在下载管理里看到它、知道占了多少空间、
/// 能续传或删除；而不是"弹个失败就消失、空间不知去向"。
class DownloadTask {
  final String id;
  final String url;
  final String fileName;

  /// downloading / paused / failed / completed
  final String status;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final DateTime updatedAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    this.error,
    required this.updatedAt,
  });

  bool get isActive => status == 'downloading';
  bool get isFailed => status == 'failed';
  bool get isCompleted => status == 'completed';

  String get receivedLabel => _formatBytes(receivedBytes);
  String get totalLabel =>
      totalBytes > 0 ? _formatBytes(totalBytes) : '未知大小';

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'status': status,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        if (error != null) 'error': error,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DownloadTask fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        status: json['status'] as String? ?? 'failed',
        receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  DownloadTask copyWith({
    String? status,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    bool clearError = false,
  }) =>
      DownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        status: status ?? this.status,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        error: clearError ? null : (error ?? this.error),
        updatedAt: DateTime.now(),
      );
}

/// 下载任务的持久化存储（原子写）。
class DownloadTaskStore {
  static const _maxTasks = 50;

  static Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'downloads'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'tasks.json'));
  }

  static Future<List<DownloadTask>> list() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final tasks = decoded
          .whereType<Map>()
          .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return tasks;
    } catch (e) {
      debugPrint('[DownloadTasks] 读取失败: $e');
      return [];
    }
  }

  static Future<void> upsert(DownloadTask task) async {
    try {
      final tasks = await list();
      tasks.removeWhere((t) => t.id == task.id);
      tasks.insert(0, task);
      if (tasks.length > _maxTasks) tasks.removeRange(_maxTasks, tasks.length);
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          jsonEncode(tasks.map((t) => t.toJson()).toList()),
          flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[DownloadTasks] 写入失败: $e');
    }
  }

  static Future<void> remove(String id) async {
    try {
      final tasks = await list();
      tasks.removeWhere((t) => t.id == id);
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
          jsonEncode(tasks.map((t) => t.toJson()).toList()),
          flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[DownloadTasks] 删除失败: $e');
    }
  }
}
