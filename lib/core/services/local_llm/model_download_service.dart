import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'download_task_store.dart';
import 'model_capabilities.dart';
import 'model_storage_settings.dart';

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
  DateTime? _lastTaskWrite;
  static const int _maxAutoRetries = 3;
  static const Duration _progressNotifyInterval = Duration(milliseconds: 120);
  static final Set<String> _activeFiles = <String>{};
  final Map<String, DateTime> _lastProgressNotify = {};

  /// 错误信息去掉签名 URL（用户看不懂，而且很长）。
  static String _cleanError(String raw) {
    var text = raw.replaceAll(RegExp(r'https?://\S+'), '（下载源）');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

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
  /// 模型目录：跟随"存储位置"设置（默认应用私有；
  /// 可切公共下载目录，权限不足会自动回退并给出提示）。
  static Future<Directory> modelsDir() async {
    final (dir, warning) = await ModelStorageSettings.resolveDir();
    if (warning != null) {
      debugPrint('[Download] $warning');
      lastStorageWarning = warning;
    }
    return dir;
  }

  /// 最近一次目录回退的原因（界面可提示一次）。
  static String? lastStorageWarning;

  /// 不考虑用户设置的"默认私有目录"（迁移时比对源目录用）。
  static Future<Directory> privateModelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'models'));
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
    int retryCount = 0,
  }) async {
    // 清除上次可能残留的取消标记。
    _cancelRequested.remove(taskId);
    // 仓库里的文件可能带子目录（如 Q4_K_M/xxx.gguf）：只取文件名，
    // 否则 p.join 会拼出不存在的父目录、openWrite 直接 ENOENT。
    final rawName = expectedFileName ??
        url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    final fileName = p.basename(rawName);
    // 同一文件只允许一个下载在跑（按文件名互斥，不看 taskId——
    // 商店页/广场页/下载管理各自的 taskId 不同，此前从这里漏进来了
    // 第二个并发下载，同一模型在下载管理里出现两张同时跑的卡片）。
    // 自动重试是递归调用（retryCount>0），不算重复。
    if (retryCount == 0) {
      if (_activeFiles.contains(fileName)) {
        throw StateError('「$fileName」正在下载中，请到下载管理查看进度');
      }
      _activeFiles.add(fileName);
    }
    try {
      return await _downloadInner(url, taskId,
          onProgress: onProgress, fileName: fileName, retryCount: retryCount);
    } finally {
      if (retryCount == 0) _activeFiles.remove(fileName);
    }
  }

  /// 某个文件名当前是否正在下载（跨页面统一判断用）。
  bool isFileDownloading(String fileName) => _activeFiles.contains(fileName);

  Future<File> _downloadInner(
    String url,
    String taskId, {
    void Function(int received, int total)? onProgress,
    required String fileName,
    required int retryCount,
  }) async {
    final dir = await modelsDir();
    final finalPath = p.join(dir.path, fileName);
    final partPath = '$finalPath.part';
    final partFile = File(partPath);
    final finalFile = File(finalPath);

    // 记录下载来源（sidecar）：未完成的下载可在下载管理里续传/删除。
    await _writeSidecar(finalPath, url, fileName);
    // 任务记录（持久化）：失败/中断也留痕，用户在下载管理里看得到、能续传。
    await _recordTask(
      taskId: taskId,
      url: url,
      fileName: fileName,
      status: 'downloading',
      receivedBytes: partFile.existsSync() ? partFile.lengthSync() : 0,
      totalBytes: 0,
    );

    // 已完成的文件直接返回。
    if (finalFile.existsSync() &&
        !partFile.existsSync() &&
        finalFile.lengthSync() > 0) {
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        receivedBytes: finalFile.lengthSync(),
        totalBytes: finalFile.lengthSync(),
        status: DownloadStatus.completed,
      );
      await _deleteSidecar(finalPath);
      await _recordTask(
        taskId: taskId,
        url: url,
        fileName: fileName,
        status: 'completed',
        receivedBytes: finalFile.lengthSync(),
        totalBytes: finalFile.lengthSync(),
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
        // Range 超出只有在服务端明确报告的总长度等于本地文件长度时，
        // 才能认定下载完整。之前无条件 rename，会把损坏/截断的 .part
        // 文件显示成已完成，随后模型加载或投影挂载才暴露问题。
        final contentRange = response.headers.value('content-range');
        final totalFromRange = contentRange == null
            ? null
            : int.tryParse(
                RegExp(r'/([0-9]+)$').firstMatch(contentRange)?.group(1) ?? '');
        final localLength = partFile.lengthSync();
        if (totalFromRange == null || localLength != totalFromRange) {
          await response.drain<void>();
          throw HttpException(
              '下载未完成：本地 $localLength 字节，服务端应为 ${totalFromRange ?? '未知'} 字节');
        }
        await response.drain<void>();
        _progressMap[taskId] = DownloadProgress(
          taskId: taskId,
          url: url,
          filePath: finalPath,
          receivedBytes: effectiveStart,
          totalBytes: effectiveStart,
          status: DownloadStatus.completed,
        );
        await _deleteSidecar(finalPath);
        await _recordTask(
          taskId: taskId,
          url: url,
          fileName: fileName,
          status: 'completed',
          receivedBytes: effectiveStart,
          totalBytes: effectiveStart,
        );
        _notify(taskId);
        await partFile.rename(finalPath);
        return finalFile;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载失败: HTTP ${response.statusCode}');
      }

      final contentLength = response.headers.value('content-length');
      final contentRange = response.headers.value('content-range');
      final totalFromRange = contentRange == null
          ? null
          : int.tryParse(
              RegExp(r'/([0-9]+)$').firstMatch(contentRange)?.group(1) ?? '');
      final totalSize = totalFromRange ??
          (contentLength != null
              ? int.tryParse(contentLength)! + effectiveStart
              : 0);
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
          await _recordTask(
            taskId: taskId,
            url: url,
            fileName: fileName,
            status: 'paused',
            receivedBytes: received,
            totalBytes: totalSize,
          );
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
        // 进度落盘做节流：每 3 秒一次，避免频繁写文件。
        final now = DateTime.now();
        if (_lastTaskWrite == null ||
            now.difference(_lastTaskWrite!) > const Duration(seconds: 3)) {
          _lastTaskWrite = now;
          unawaited(_recordTask(
            taskId: taskId,
            url: url,
            fileName: fileName,
            status: 'downloading',
            receivedBytes: received,
            totalBytes: totalSize,
          ));
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (totalSize > 0 && received != totalSize) {
        throw HttpException('下载未完成：已接收 $received 字节，应为 $totalSize 字节');
      }

      // 下载完成，rename .part → 正式文件。
      await partFile.rename(finalPath);
      await _deleteSidecar(finalPath);
      await _recordTask(
        taskId: taskId,
        url: url,
        fileName: fileName,
        status: 'completed',
        receivedBytes: received,
        totalBytes: totalSize,
      );

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
      // 连接被中断（CDN 常见）：自动重试几次，用 Range 从断点继续。
      final message = e.toString();
      final retriable = retryCount < _maxAutoRetries &&
          partFile.existsSync() &&
          (message.contains('Connection closed') ||
              message.contains('Connection reset') ||
              message.contains('Connection terminated') ||
              message.contains('SocketException') ||
              message.contains('timed out') ||
              message.contains('Software caused connection abort'));
      if (retriable) {
        final nextRetry = retryCount + 1;
        debugPrint('[Download] 连接中断，自动重试第 $nextRetry 次（断点续传）');
        _progressMap[taskId] = DownloadProgress(
          taskId: taskId,
          url: url,
          filePath: finalPath,
          status: DownloadStatus.downloading,
          error: '连接中断，正在自动重试（第 $nextRetry 次）',
        );
        _notify(taskId);
        await Future<void>.delayed(Duration(seconds: 2 * nextRetry));
        return download(url, taskId,
            onProgress: onProgress,
            expectedFileName: fileName,
            retryCount: nextRetry);
      }
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: finalPath,
        status: DownloadStatus.failed,
        error: _cleanError(message),
      );
      _notify(taskId);
      // 失败也留痕：已下载的部分保留（.part 不删），记录错误供界面解释。
      await _recordTask(
        taskId: taskId,
        url: url,
        fileName: fileName,
        status: 'failed',
        receivedBytes: partFile.existsSync() ? partFile.lengthSync() : 0,
        totalBytes: 0,
        error: _cleanError(message),
      );
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

  /// 列出已下载的模型文件。
  /// **排除 .part 临时文件与 mmproj 视觉投影**：投影是模型的附件，
  /// 不能当成独立模型列出来（否则会出现"点进去加载失败"的假模型）。
  static Future<List<File>> listDownloadedModels() async {
    final dir = await modelsDir();
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) {
      if (!f.path.endsWith('.gguf') || f.path.endsWith('.gguf.part')) {
        return false;
      }
      if (File('${f.path}.part').existsSync() || f.lengthSync() <= 0) {
        return false;
      }
      return !ModelCapabilities.isProjectorFile(f.uri.pathSegments.last);
    }).toList();
  }

  /// 列出已下载的视觉投影附件。
  static Future<List<File>> listProjectors() async {
    final dir = await modelsDir();
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) {
      if (!ModelCapabilities.isProjectorFile(f.uri.pathSegments.last)) {
        return false;
      }
      return f.lengthSync() > 0 && !File('${f.path}.part').existsSync();
    }).toList();
  }

  /// 获取指定 URL 对应的本地文件路径。
  static Future<String> localPathFor(String url) async {
    final dir = await modelsDir();
    final fileName = url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    return p.join(dir.path, fileName);
  }

  /// 记录/更新持久化任务（失败与暂停都会留痕）。
  static Future<void> _recordTask({
    required String taskId,
    required String url,
    required String fileName,
    required String status,
    required int receivedBytes,
    required int totalBytes,
    String? error,
  }) async {
    await DownloadTaskStore.upsert(DownloadTask(
      id: taskId,
      url: url,
      fileName: fileName,
      status: status,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      error: error,
      updatedAt: DateTime.now(),
    ));
  }

  void _notify(String taskId) {
    final progress = _progressMap[taskId];
    if (progress == null) return;
    final now = DateTime.now();
    final previous = _lastProgressNotify[taskId];
    final isTerminal = progress.status == DownloadStatus.completed ||
        progress.status == DownloadStatus.failed ||
        progress.status == DownloadStatus.cancelled ||
        progress.status == DownloadStatus.paused;
    if (!isTerminal &&
        previous != null &&
        now.difference(previous) < _progressNotifyInterval) {
      return;
    }
    _lastProgressNotify[taskId] = now;
    _progressController.add(progress);
  }

  void dispose() {
    _progressController.close();
    _client.close(force: true);
  }
}
