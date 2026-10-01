import 'dart:async';
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

/// 模型下载管理器：流式下载 + HTTP Range 断点续传 + 进度流。
///
/// 文件保存到应用支持目录下的 `models/` 子目录。
/// 中断后重新调用 [download] 会自动从已下载的字节数处续传。
class ModelDownloadService {
  ModelDownloadService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Map<String, DownloadProgress> _progressMap = {};
  final _progressController = StreamController<DownloadProgress>.broadcast();

  /// 广播下载进度变化。
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  DownloadProgress? progressFor(String taskId) => _progressMap[taskId];

  /// 是否正在下载指定任务。
  bool isDownloading(String taskId) =>
      _progressMap[taskId]?.status == DownloadStatus.downloading;

  /// 获取模型存储目录。
  static Future<Directory> modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 从 URL 下载 GGUF 文件到本地模型目录（支持断点续传）。
  ///
  /// [taskId] 标识下载任务（通常为模型 id）。
  /// [onProgress] 每收到一块数据回调 (已接收字节, 总字节)。
  /// 返回下载完成的本地文件。
  Future<File> download(
    String url,
    String taskId, {
    void Function(int received, int total)? onProgress,
    String? expectedFileName,
  }) async {
    final dir = await modelsDir();
    final fileName = expectedFileName ??
        url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);

    // 断点续传：检查已存在的部分文件
    var startByte = 0;
    if (file.existsSync()) startByte = file.lengthSync();

    _progressMap[taskId] = DownloadProgress(
      taskId: taskId,
      url: url,
      filePath: filePath,
      receivedBytes: startByte,
      totalBytes: 0,
      status: DownloadStatus.downloading,
    );
    _notify(taskId);

    try {
      final request = await _client.getUrl(Uri.parse(url));
      if (startByte > 0) {
        request.headers.set('Range', 'bytes=$startByte-');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));

      // 200 = 全量（服务器不支持 Range），重置起点
      if (response.statusCode == 200 && startByte > 0) startByte = 0;
      if (response.statusCode == 416) {
        // 文件已完整
        await response.drain<void>();
        _complete(taskId, filePath);
        return file;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('下载失败: HTTP ${response.statusCode}');
      }

      final contentLength = response.headers.value('content-length');
      final totalSize =
          contentLength != null ? int.parse(contentLength) + startByte : 0;
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: filePath,
        receivedBytes: startByte,
        totalBytes: totalSize,
        status: DownloadStatus.downloading,
      );

      final sink = file.openWrite(mode: FileMode.append);
      var received = startByte;

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        _progressMap[taskId] = DownloadProgress(
          taskId: taskId,
          url: url,
          filePath: filePath,
          receivedBytes: received,
          totalBytes: totalSize,
          status: DownloadStatus.downloading,
        );
        onProgress?.call(received, totalSize);
        _notify(taskId);
      }

      await sink.flush();
      await sink.close();

      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: filePath,
        receivedBytes: received,
        totalBytes: totalSize,
        status: DownloadStatus.completed,
      );
      _notify(taskId);
      return file;
    } catch (e) {
      _progressMap[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: filePath,
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
  }

  /// 列出已下载的模型文件。
  static Future<List<File>> listDownloadedModels() async {
    final dir = await modelsDir();
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .toList();
  }

  /// 获取指定 URL 对应的本地文件路径。
  static Future<String> localPathFor(String url) async {
    final dir = await modelsDir();
    final fileName = url.split('/').last.replaceAll(RegExp(r'[?#].*$'), '');
    return p.join(dir.path, fileName);
  }

  void _complete(String taskId, String filePath) {
    _progressMap[taskId] = DownloadProgress(
      taskId: taskId,
      url: '',
      filePath: filePath,
      status: DownloadStatus.completed,
    );
    _notify(taskId);
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

/// 下载被用户取消。
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => '下载已取消';
}
