import 'dart:async';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

import 'model_catalog.dart';

/// 本地推理引擎封装：加载 GGUF 模型、流式生成、对话会话。
/// 线程安全：同一时刻只允许加载一个模型。
class LocalLlmEngine {
  LlamaEngine? _engine;
  String? _loadedModelPath;
  bool _disposed = false;

  String? get loadedModelPath => _loadedModelPath;
  bool get isLoaded => _engine != null && _loadedModelPath != null;

  /// 从本地文件路径加载 GGUF 模型。
  Future<void> loadModel(String filePath, {int contextSize = 4096}) async {
    if (_disposed) throw StateError('引擎已释放');
    await unload();
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModelSource(
      ModelSource.path(filePath),
      modelParams: ModelParams(contextSize: contextSize),
    );
    _engine = engine;
    _loadedModelPath = filePath;
  }

  /// 非流式生成：发送消息列表，返回完整回复文本。
  Future<String> generate(
    List<LlamaChatMessage> messages, {
    int maxTokens = 1024,
    double temp = 0.8,
  }) async {
    final engine = _engine;
    if (engine == null) throw StateError('模型未加载');
    final buffer = StringBuffer();
    await for (final chunk in engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: temp),
    )) {
      final text = chunk.choices.first.delta.content;
      if (text != null) buffer.write(text);
    }
    return buffer.toString();
  }

  /// 流式生成：逐帧产出增量文本。
  Stream<String> generateStream(
    List<LlamaChatMessage> messages, {
    int maxTokens = 1024,
    double temp = 0.8,
  }) async* {
    final engine = _engine;
    if (engine == null) throw StateError('模型未加载');
    await for (final chunk in engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: temp),
    )) {
      final text = chunk.choices.first.delta.content;
      if (text != null && text.isNotEmpty) yield text;
    }
  }

  /// 卸载当前模型（释放内存）。
  Future<void> unload() async {
    final engine = _engine;
    if (engine != null) {
      await engine.dispose();
      _engine = null;
      _loadedModelPath = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await unload();
  }
}

/// 已下载的本地模型记录。
class DownloadedModel {
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final String? modelId; // 关联到目录中的模型 id

  const DownloadedModel({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    this.modelId,
  });

  String get name => fileName.replaceAll(RegExp(r'\.gguf$'), '');
  String get sizeMb =>
      '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  static DownloadedModel fromFile(File file, {String? modelId}) =>
      DownloadedModel(
        filePath: file.path,
        fileName: file.uri.pathSegments.last,
        fileSizeBytes: file.lengthSync(),
        modelId: modelId,
      );
}

/// 从 LocalModelCatalog 的模型获取对应的本地文件路径（如果已下载）。
Future<DownloadedModel?> findDownloaded(
    LocalModelInfo info, String modelsDirPath) async {
  final fileName = info.downloadUrl.split('/').last;
  final filePath = '$modelsDirPath/$fileName';
  final file = File(filePath);
  if (file.existsSync()) {
    return DownloadedModel.fromFile(file, modelId: info.id);
  }
  return null;
}
