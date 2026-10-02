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
  bool _supportsNoThink = false;
  String? _projectorPath;
  String? _pendingProjectorPath;
  String? _projectorError;
  bool _disposed = false;

  String? get loadedModelPath => _loadedModelPath;

  /// 当前模型是否真的能看图（取决于是否成功加载了视觉投影 mmproj）。
  bool get supportsVision => _visionAvailable;

  /// 已加载的视觉投影文件路径（没有则为 null）。
  String? get projectorPath => _projectorPath;

  bool get isLoaded => _engine != null && _loadedModelPath != null;

  /// 从本地文件路径加载 GGUF 模型。
  ///
  /// **不在加载时自动挂载视觉投影**：mmproj 是模型专用的，挂错会把引擎带进
  /// 不匹配的多模态路径，连文本对话一起报错（上一版就是这么坏掉的）。
  /// 这里只"记账"（找到同系列候选投影并记下来），真正启用走 [ensureVision]，
  /// 由用户在发图片时按需触发；文本对话永远不受影响。
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
    _visionAvailable = false;
    _projectorError = null;
    _supportsNoThink =
        ModelCapabilities.supportsNoThinkDirective(filePath);
    _pendingProjectorPath = mmProjPath ?? _matchingProjector(filePath);
    if (_pendingProjectorPath != null) {
      debugPrint('[LocalLlm] 发现匹配的视觉投影（待启用）: $_pendingProjectorPath');
    }
  }

  /// 是否存在可用的视觉投影候选（界面据此提示"可启用看图"）。
  bool get hasVisionCandidate => _pendingProjectorPath != null;

  /// 当前模型是否认得 `/no_think`（只有 Qwen3 系）。
  bool get supportsNoThinkDirective => _supportsNoThink;

  /// 视觉投影启用失败的原因（界面向用户解释用）。
  String? get projectorError => _projectorError;

  /// 按需启用视觉投影（用户要发图片时调用）。
  ///
  /// 失败一律回退纯文本：先确保卸载残留投影，再返回 false——绝不允许
  /// "投影坏了导致连文本都不能用"。
  Future<bool> ensureVision() async {
    if (_visionAvailable) return true;
    final engine = _engine;
    final projector = _pendingProjectorPath;
    if (engine == null || projector == null) return false;
    try {
      await engine
          .loadMultimodalProjector(projector)
          .timeout(const Duration(seconds: 45));
      _projectorPath = projector;
      _visionAvailable = await engine.supportsVision;
      _projectorError = null;
      debugPrint('[LocalLlm] 视觉投影已启用: $projector '
          '(supportsVision=$_visionAvailable)');
      return _visionAvailable;
    } catch (e) {
      debugPrint('[LocalLlm] 视觉投影启用失败，回退纯文本: $e');
      _projectorError = '$e';
      _visionAvailable = false;
      _projectorPath = null;
      // 关键：无论失败原因是什么，都把投影彻底卸掉，保证之后的文本生成
      // 走纯文本路径（不匹配的 mtmd context 会让所有生成都失败）。
      try {
        await engine.unloadMultimodalProjector();
      } catch (_) {}
      return false;
    }
  }

  /// 在同目录查找**与主模型匹配**的视觉投影。
  ///
  /// mmproj 不通用（投影层维度必须与主模型隐藏维度一致），所以：
  /// 1) 优先文件名包含主模型核心名（如 `mmproj-gemma-3-4b-it-f16.gguf` 配
  ///    `gemma-3-4b-it-Q4_K_M.gguf`）；
  /// 2) 通用名（`mmproj-F16.gguf`）只在目录里只有这一个主模型时接受；
  /// 3) 匹配不上的投影一律忽略（绝不猜）。
  static String? _matchingProjector(String modelPath) {
    try {
      final file = File(modelPath);
      final dir = file.parent;
      if (!dir.existsSync()) return null;
      final projectors = <File>[];
      final mainModels = <File>[];
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (ModelCapabilities.isProjectorFile(name)) {
          projectors.add(entity);
        } else if (name.toLowerCase().endsWith('.gguf')) {
          mainModels.add(entity);
        }
      }
      if (projectors.isEmpty) return null;
      final core = ModelCapabilities.coreToken(
          file.uri.pathSegments.last);
      for (final projector in projectors) {
        final name = projector.uri.pathSegments.last.toLowerCase();
        if (name.contains(core)) return projector.path;
      }
      if (projectors.length == 1 && mainModels.length == 1) {
        return projectors.first.path;
      }
      return null;
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
    bool suppressThinking = false,
  }) async* {
    final engine = _engine;
    if (engine == null) throw StateError('模型未加载');
    // 只有认这个指令的家族（Qwen3 系）才追加 /no_think：别的模型会把它当
    // 可疑文本反复琢磨，导致思考打转（真机实测 Spark-X2.5 死循环）。
    final effectiveMessages =
        (suppressThinking && !thinkingEnabled && _supportsNoThink)
            ? _withNoThink(messages)
            : messages;
    await for (final chunk in engine.create(
      effectiveMessages,
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

  /// 给最后一条用户消息追加 `/no_think`（Qwen3 系用于关闭思考的指令）。
  /// 只处理纯文本消息；已有该指令时不重复添加。
  static List<LlamaChatMessage> _withNoThink(List<LlamaChatMessage> messages) {
    if (messages.isEmpty) return messages;
    final result = List<LlamaChatMessage>.from(messages);
    final last = result.last;
    // 只处理纯文本消息（有图片等多模态内容时不动，避免破坏结构）。
    if (last.parts.length != 1 ||
        last.parts.first is! LlamaTextContent) {
      return result;
    }
    final text = last.content;
    if (text.isEmpty || text.contains('/no_think')) return result;
    result[result.length - 1] = LlamaChatMessage.fromText(
      role: last.role,
      text: '$text\n/no_think',
    );
    return result;
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
      _pendingProjectorPath = null;
      _projectorError = null;
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
