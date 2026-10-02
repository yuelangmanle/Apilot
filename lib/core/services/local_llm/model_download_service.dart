import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 下载状态。
enum DownloadStatus { idle, downloading, paused, completed, failed, cancelled }

/// 单个下载任务的进度快照。
class DownloadProgress {
  final String taskId;
  final String url;
  final String filePath;
  final int receivedBytes;
  final int totalBytes;
  final DownloadStatus status;
  final String? error;

  const DownloadProgress({
    required this.taskId,
    required this.url,
    required this.filePath,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.status = DownloadStatus.idle,
    this.error,
  });

  double get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  bool get isDone => status == DownloadStatus.completed;

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.paused;
}

/// 下载被用户取消。
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => '下载已取消';
}

/// 未完成的下载（`.part` 文件），可在下载管理里续传或删除。
class PartialDownload {
  final String url;
  final String fileName;
  final String partialPath;
  final int receivedBytes;

  const PartialDownload({
    required this.url,
    required this.fileName,
    required this.partialPath,
    required this.receivedBytes,
  });

  String get receivedLabel => receivedBytes >= 1024 * 1024 * 1024
      ? '${(receivedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(receivedBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  /// sidecar 丢失（老版本下载）时为 true：只能删除，不能续传。
  bool get resumable => url.isNotEmpty;
}

/// 模型下载管理器：流式下载 + HTTP Range 断点续传 + 进度流 + 取消支持。
///
/// 应级注册为单例（App 生命周期共享同一实例）以避免并发写入。
/// 下载期间使用 `.part` 后缀，完成后原子 rename 到正式文件名。
class ModelDownloadService {
  ModelDownloadService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, DownloadProgress> _progressMap = {};
  final Set<String> _cancelRequested = {};
  final _progressController = StreamController<DownloadProgress>.broadcast();

  /// 广播下载进度变化。
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  DownloadProgress? progressFor(String taskId) => _progressMap[taskId];

  bool isDownloading(String taskId) =>
      _progressMap[taskId]?.status == DownloadStatus.downloading;

  /// 请求取消指定任务（在下一个数据块边界生效）。
  void cancel(String taskId) {
    _cancelRequested.add(taskId);
  }

  /// 获取模型存储目录。
  static Future<Directory> modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 下载 GGUF 文件到本地模型目录（支持断点续传 + 取消）。
  ///
  /// 使用 `.part` 临时文件下载，完成后原子 rename 到正式文件名。
  /// 已存在的同名 `.part` 文件会自动续传。
  Future<File> download(
    String url,
    String taskId, {
    void Function(int received, int total)? onProgress,
    String? expectedFileName,
  }) async {
    // 清除上次可能残留的取消标记。
    _cancelRequested.remove(taskId);

    final dir = await modelsDir();
    final fileName = expectedFileName ??
        url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    final finalPath = p.join(dir.path, fileName);
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    final finalFile = File(finalPath);

    // 记录下载来源（sidecar）：未完成的下载可在下载管理里续传/删除。
    await _writeSidecar(finalPath, url, fileName);

    // 已完成的文件直接返回。
    if (finalFile.existsSync() && !partFile.existsSync()) {
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        receivedBytes: finalFile.lengthSync(),
        totalBytes: finalFile.lengthSync(),
        status: DownloadStatus.completed,
      );
      _notify(taskId);
      return finalFile;
    }

    // 断点续传：从 .part 文件续传。
    var startByte = 0;
    if (partFile.existsSync()) startByte = partFile.lengthSync();

    _progressMap[taskId] = DownloadProgress(
      taskId: taskId,
      url: url,
      filePath: finalPath,
      receivedBytes: startByte,
      totalBytes: 0,
      status: DownloadStatus.downloading,
    );
    _notify(taskId);

    IOSink? sink;
    try {
      final request = await _client.getUrl(Uri.parse(url));
      if (startByte > 0) {
        request.headers.set('Range', 'bytes=$startByte-');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));

      var effectiveStart = startByte;
      if (response.statusCode == 200 && startByte > 0) {
        // 服务器不支持 Range → 从头下载，截断 .part 文件。
        effectiveStart = 0;
        await partFile.delete();
      }
      if (response.statusCode == 416) {
        // Range 超出：文件可能已完整。
        await response.drain<void>();
        _progressMap[taskId] = DownloadProgress(
          taskId: taskId,
          url: url,
          filePath: finalPath,
          receivedBytes: effectiveStart,
          totalBytes: effectiveStart,
          status: DownloadStatus.completed,
        );
        _notify(taskId);
        partFile.renameSync(finalPath);
        return finalFile;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载失败: HTTP ${response.statusCode}');
      }

      final contentLength = response.headers.value('content-length');
      final totalSize =
          contentLength != null ? int.parse(contentLength) + effectiveStart : 0;
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        receivedBytes: effectiveStart,
        totalBytes: totalSize,
        status: DownloadStatus.downloading,
      );
      _notify(taskId);

      // 用 .part 文件写入，完成后再 rename。
      sink = partFile.openWrite(mode: FileMode.append);
      var received = effectiveStart;

      await for (final chunk in response) {
        if (_cancelRequested.contains(taskId)) {
          await sink.flush();
          await sink.close();
          _cancelRequested.remove(taskId);
          _progressMap[taskId] = DownloadProgress(
            taskId: taskId,
            url: url,
            filePath: finalPath,
            receivedBytes: received,
            totalBytes: totalSize,
            status: DownloadStatus.paused,
          );
          _notify(taskId);
          throw const DownloadCancelledException();
        }
        received += chunk.length;
        sink.add(chunk);
        _progressMap[taskId] = DownloadProgress(
          taskId: taskId,
          url: url,
          filePath: finalPath,
          receivedBytes: received,
          totalBytes: totalSize,
          status: DownloadStatus.downloading,
        );
        onProgress?.call(received, totalSize);
        _notify(taskId);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // 下载完成，rename .part → 正式文件。
      await partFile.rename(finalPath);
      await _deleteSidecar(finalPath);

      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        receivedBytes: received,
        totalBytes: totalSize,
        status: DownloadStatus.completed,
      );
      _notify(taskId);
      return finalFile;
    } catch (e) {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      _notify(taskId);
      rethrow;
    }
  }

  /// 删除已下载的模型文件。
  static Future<void> deleteModelFile(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) await file.delete();
    final partFile = File('$filePath.part');
    if (partFile.existsSync()) await partFile.delete();
    await _deleteSidecar(filePath);
  }

  /// 已下载的模型继续下载/删除时用的 sidecar 路径。
  static String _sidecarPath(String finalPath) => '$finalPath.meta.json';

  static Future<void> _writeSidecar(
      String finalPath, String url, String fileName) async {
    try {
      await File(_sidecarPath(finalPath)).writeAsString(
        jsonEncode({
          'url': url,
          'fileName': fileName,
          'createdAt': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<void> _deleteSidecar(String finalPath) async {
    try {
      final file = File(_sidecarPath(finalPath));
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// 列出未完成的下载（`.part` 文件），用于下载管理页续传/删除。
  static Future<List<PartialDownload>> listPartialDownloads() async {
    final dir = await modelsDir();
    if (!dir.existsSync()) return [];
    final results = <PartialDownload>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.part')) continue;
      final finalPath = file.path.substring(0, file.path.length - 5);
      var url = '';
      var fileName = p.basename(finalPath);
      try {
        final sidecar = File(_sidecarPath(finalPath));
        if (sidecar.existsSync()) {
          final decoded = jsonDecode(await sidecar.readAsString());
          if (decoded is Map) {
            url = decoded['url'] as String? ?? '';
            fileName = decoded['fileName'] as String? ?? fileName;
          }
        }
      } catch (_) {}
      results.add(PartialDownload(
        url: url,
        fileName: fileName,
        partialPath: file.path,
        receivedBytes: file.lengthSync(),
      ));
    }
    results.sort((a, b) => b.receivedBytes.compareTo(a.receivedBytes));
    return results;
  }

  /// 列出已下载的模型文件（排除 .part 临时文件）。
  static Future<List<File>> listDownloadedModels() async {
    final dir = await modelsDir();
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.gguf') && !f.path.endsWith('.gguf.part'))
        .toList();
  }

  /// 获取指定 URL 对应的本地文件路径。
  static Future<String> localPathFor(String url) async {
    final dir = await modelsDir();
    final fileName = url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    return p.join(dir.path, fileName);
  }

  void _notify(String taskId) {
    final progress = _progressMap[taskId];
    if (progress != null) _progressController.add(progress);
  }

  void dispose() {
    _progressController.close();
    _client.close(force: true);
  }
}
