import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'model_capabilities.dart';
import 'model_catalog.dart';

/// 本地推理引擎封装：加载 GGUF 模型、流式生成、对话会话。
/// 线程安全：同一时刻只允许加载一个模型。
class LocalLlmEngine {
  LlamaEngine? _engine;
  String? _loadedModelPath;
  bool _visionAvailable = false;
  String? _projectorPath;
  bool _disposed = false;

  String? get loadedModelPath => _loadedModelPath;

  /// 当前模型是否真的能看图（取决于是否成功加载了视觉投影 mmproj）。
  bool get supportsVision => _visionAvailable;

  /// 已加载的视觉投影文件路径（没有则为 null）。
  String? get projectorPath => _projectorPath;

  bool get isLoaded => _engine != null && _loadedModelPath != null;

  /// 从本地文件路径加载 GGUF 模型。
  ///
  /// [mmProjPath] 显式指定视觉投影文件；不传时自动在同目录查找
  /// `mmproj*.gguf`——多模态模型靠它才能看图，缺了它就是纯文本行为。
  Future<void> loadModel(
    String filePath, {
    int contextSize = 4096,
    String? mmProjPath,
  }) async {
    if (_disposed) throw StateError('引擎已释放');
    await unload();
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModelSource(
      ModelSource.path(filePath),
      modelParams: ModelParams(contextSize: contextSize),
    );
    _engine = engine;
    _loadedModelPath = filePath;

    // 视觉投影：失败不影响文本能力，只是没有看图能力。
    final projector = mmProjPath ?? _findSiblingProjector(filePath);
    if (projector != null) {
      try {
        await engine.loadMultimodalProjector(projector);
        _projectorPath = projector;
        _visionAvailable = await engine.supportsVision;
        debugPrint('[LocalLlm] 视觉投影已加载: $projector '
            '(supportsVision=$_visionAvailable)');
      } catch (e) {
        debugPrint('[LocalLlm] 视觉投影加载失败（按纯文本处理）: $e');
        _projectorPath = null;
        _visionAvailable = false;
      }
    }
  }

  /// 在同目录查找视觉投影文件（mmproj*.gguf）。
  static String? _findSiblingProjector(String modelPath) {
    try {
      final file = File(modelPath);
      final dir = file.parent;
      if (!dir.existsSync()) return null;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (ModelCapabilities.isProjectorFile(name)) return entity.path;
      }
    } catch (_) {}
    return null;
  }

  /// 非流式生成：发送消息列表，返回完整回复文本。
  Future<String> generate(
    List<LlamaChatMessage> messages, {
    int maxTokens = 1024,
    double temp = 0.8,
    double topP = 0.9,
  }) async {
    final engine = _engine;
    if (engine == null) throw StateError('模型未加载');
    final buffer = StringBuffer();
    await for (final chunk in engine.create(
      messages,
      params: GenerationParams(maxTokens: maxTokens, temp: temp, topP: topP),
    )) {
      final text = chunk.choices.first.delta.content;
      if (text != null) buffer.write(text);
    }
    return buffer.toString();
  }

  /// 流式生成：逐帧产出增量（正文 + 思考过程分离）。
  ///
  /// [thinkingEnabled] 为 true 时启用思考预算（部分推理模型支持），
  /// 思考内容经 [LocalLlmChunk.thinking] 单独产出，界面可折叠展示。
  Stream<LocalLlmChunk> generateStream(
    List<LlamaChatMessage> messages, {
    int maxTokens = 1024,
    double temp = 0.8,
    double topP = 0.9,
    bool thinkingEnabled = false,
  }) async* {
    final engine = _engine;
    if (engine == null) throw StateError('模型未加载');
    await for (final chunk in engine.create(
      messages,
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: temp,
        topP: topP,
        thinkingBudget: thinkingEnabled
            ? const ThinkingBudget(maxTokens: 1024)
            : null,
      ),
    )) {
      final delta = chunk.choices.first.delta;
      final content = delta.content;
      final thinking = delta.thinking;
      if ((content != null && content.isNotEmpty) ||
          (thinking != null && thinking.isNotEmpty)) {
        yield LocalLlmChunk(content: content, thinking: thinking);
      }
    }
  }

  /// 卸载当前模型（释放内存）。
  Future<void> unload() async {
    final engine = _engine;
    if (engine != null) {
      await engine.dispose();
      _engine = null;
      _loadedModelPath = null;
      _visionAvailable = false;
      _projectorPath = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await unload();
  }
}

/// 流式增量：content 与 thinking 分离（推理模型的思考过程可折叠展示）。
class LocalLlmChunk {
  final String? content;
  final String? thinking;

  const LocalLlmChunk({this.content, this.thinking});
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
