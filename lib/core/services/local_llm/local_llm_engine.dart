import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'local_llm_tuning.dart';
import 'model_capabilities.dart';
import 'model_storage_settings.dart';
import 'model_catalog.dart';

/// 本地推理引擎封装：加载 GGUF 模型、流式生成、对话会话。
/// 线程安全：同一时刻只允许一个加载在跑（内部互斥），同一时刻只允许加载一个模型。
class LocalLlmEngine {
  LlamaEngine? _engine;
  String? _loadedModelPath;
  bool _visionAvailable = false;
  bool _supportsNoThink = false;
  String? _projectorPath;
  String? _pendingProjectorPath;
  String? _projectorError;
  bool _disposed = false;
  Future<bool>? _visionLoadFuture;

  /// 本次加载的模型已证实不支持投机解码（避免每轮都失败重试一次）。
  bool _speculativeUnsupported = false;

  // ---- 加载互斥 ----
  // 并发 loadModel 是真实存在过的闪退源：聊天页 initState、绑定投影、
  // 调参面板各自都能触发加载，两个 4B 模型同时进 Vulkan 编译 → 内存翻倍、
  // 引擎句柄竞争。这里把所有加载串成一条队列，并按"路径#上下文"去重。
  Future<void>? _loadQueueTail;
  String? _loadingKey;
  String? _loadedKey;

  // llama.cpp 的同一上下文不能同时生成。工具模式、聊天页和本地网关
  // 可能共享一个引擎，因此生成也必须串行化，避免 native 状态被并发读写。
  Future<void> _generationQueue = Future<void>.value();
  bool _generationBusy = false;

  String? get loadedModelPath => _loadedModelPath;

  /// 是否有加载正在进行（含排队等待）。
  bool get isLoading => _loadingKey != null;

  /// 正在加载的目标（路径#上下文）；空闲为 null。
  String? get loadingKey => _loadingKey;

  /// 当前模型是否真的能看图（取决于是否成功加载了视觉投影 mmproj）。
  bool get supportsVision => _visionAvailable;

  /// 已加载的视觉投影文件路径（没有则为 null）。
  String? get projectorPath => _projectorPath;

  bool get isLoaded => _engine != null && _loadedModelPath != null;

  bool get isDisposed => _disposed;

  bool get isGenerating => _generationBusy;

  /// 引擎当前已加载的模型是否就是 [filePath]（且没有别的加载在跑）。
  /// 界面用它判断"可以直接生成"，比 [isLoaded] 严格——isLoaded 只说明
  /// 引擎里装着*某个*模型，未必是当前会话要的那个。
  bool isReadyFor(String filePath, {int contextSize = 4096}) =>
      !isLoading && isLoaded && _loadedModelPath == filePath;

  static String _keyFor(String filePath, int contextSize) =>
      '$filePath#$contextSize';

  /// 从本地文件路径加载 GGUF 模型。
  ///
  /// **不在加载时自动挂载视觉投影**：mmproj 是模型专用的，挂错会把引擎带进
  /// 不匹配的多模态路径，连文本对话一起报错（上一版就是这么坏掉的）。
  /// 这里只"记账"（找到同系列候选投影并记下来），真正启用走 [ensureVision]，
  /// 由用户在发图片时按需触发；文本对话永远不受影响。
  ///
  /// [force] 为 true 时忽略去重（绑定投影/调参后必须真正重载）。
  /// 相同目标的重复调用会复用进行中的加载（聊天页 initState 与发送路径
  /// 同时触发时只加载一次）；不同目标则排队串行执行。
  Future<void> loadModel(
    String filePath, {
    int contextSize = 4096,
    String? mmProjPath,
    bool force = false,
  }) {
    if (_disposed) throw StateError('引擎已释放');
    final key = _keyFor(filePath, contextSize);
    if (!force) {
      // 目标正在加载 → 直接等它；目标已装好 → 立即返回。
      if (_loadingKey == key && _loadQueueTail != null) return _loadQueueTail!;
      if (_loadedKey == key && isLoaded) return Future.value();
    }
    final prev = _loadQueueTail;
    final task = _doLoad(filePath, contextSize, mmProjPath, key, prev);
    _loadQueueTail = task;
    _loadingKey = key;
    // 队尾完成后清掉"加载中"标记；失败也要清。不要直接丢弃
    // whenComplete 返回的 Future，否则原始加载异常会被派生 Future 再报一次。
    unawaited(task.then<void>(
      (_) {
        if (_loadingKey == key) _loadingKey = null;
      },
      onError: (Object _, StackTrace __) {
        if (_loadingKey == key) _loadingKey = null;
      },
    ));
    return task;
  }

  Future<void> _doLoad(
    String filePath,
    int contextSize,
    String? mmProjPath,
    String key,
    Future<void>? prev,
  ) async {
    // 等待前一个加载彻底结束（可能是别的模型，也可能是同模型的调参重载）。
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
      if (_disposed) throw StateError('引擎已释放');
    }
    cancelGeneration();
    try {
      await _generationQueue;
    } catch (_) {}
    final sw = Stopwatch()..start();
    debugPrint('[LocalLlm] 开始加载: ${filePath.split('/').last} '
        '(ctx=$contextSize)…');
    await unload();
    final engine = LlamaEngine(LlamaBackend());
    // 应用性能档位（线程 / GPU 卸载 / FlashAttention / KV 量化）。
    final threads = LocalLlmTuning.resolveThreads();
    final gpuLayers = LocalLlmTuning.resolveGpuLayers();
    // 关键：llamadart 在 Android 上把 GpuBackend.auto 解析成 **CPU**，
    // 所以"能卸就卸"其实从未生效（实测性能档=省电档）。
    // 这里显式给出后端；失败自动回退 CPU，绝不因此让模型加载不了。
    final backend = LocalLlmTuning.resolveBackend();
    debugPrint('[LocalLlm] 加载参数: ${LocalLlmTuning.describe()}'
        ' backend=${backend.name}');
    try {
      await _loadWithBackend(
          engine, filePath, contextSize, threads, gpuLayers, backend);
    } catch (e) {
      if (backend == GpuBackend.cpu) rethrow;
      debugPrint('[LocalLlm] ${backend.name} 加载失败，回退 CPU: $e');
      await _loadWithBackend(
          engine, filePath, contextSize, threads, 0, GpuBackend.cpu);
    }
    // 关键：把引擎挂到实例上（我重构后端回退时漏了这一行，
    // 结果所有推理都报 "Bad state: 模型未加载"）。
    _engine = engine;
    _loadedModelPath = filePath;
    _visionAvailable = false;
    _projectorError = null;
    _speculativeUnsupported = false;
    _supportsNoThink = ModelCapabilities.supportsNoThinkDirective(filePath);
    _pendingProjectorPath = mmProjPath ??
        await _pairedProjector(filePath) ??
        _matchingProjector(filePath);
    _loadedKey = key;
    debugPrint('[LocalLlm] 模型加载完成: ${filePath.split('/').last} '
        '耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    if (_pendingProjectorPath != null) {
      debugPrint('[LocalLlm] 发现匹配的视觉投影（待启用）: $_pendingProjectorPath');
    }
  }

  /// 用指定后端加载；后端不被支持时会抛错，由调用方回退。
  Future<void> _loadWithBackend(
    LlamaEngine engine,
    String filePath,
    int contextSize,
    int threads,
    int? gpuLayers,
    GpuBackend backend,
  ) async {
    await engine.loadModelSource(
      ModelSource.path(filePath),
      modelParams: ModelParams(
        contextSize: contextSize,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads == 0 ? 0 : math.max(threads, 4),
        // 预填充批量：给足 batch，首字更快（内存紧张时库会自动收紧）。
        batchSize: 512,
        preferredBackend: backend,
        // null → 999（= 库默认"能卸就卸"）；0 → 纯 CPU（省电档）。
        gpuLayers: gpuLayers ?? ModelParams.maxGpuLayers,
        useMmap: true,
        flashAttention: LocalLlmTuning.resolveFlashAttention(),
        cacheTypeK: LocalLlmTuning.resolveKvCacheType(),
        cacheTypeV: LocalLlmTuning.resolveKvCacheType(),
        // 开启投机解码时给原生层预留回滚快照：ngram-simple 的有效草稿长度
        // 默认 48（ngramSizeM），官方要求 snapshot ≥ 该值，否则部分架构
        // 会拒绝投机路径。关闭时为 0（不做快照，零额外开销）。
        speculativeRollbackTokenMax: LocalLlmTuning.speculativeNgram ? 64 : 0,
      ),
    );
  }

  /// 是否存在可用的视觉投影候选（界面据此提示"可启用看图"）。
  bool get hasVisionCandidate => _pendingProjectorPath != null;

  /// 当前模型是否认得 `/no_think`（只有 Qwen3 系）。
  bool get supportsNoThinkDirective => _supportsNoThink;

  /// 视觉投影启用失败的原因（界面向用户解释用）。
  String? get projectorError => _projectorError;

  /// 取消当前生成（停止按钮用）。
  /// 之前工具模式只是"忽略后续 chunk"，底层推理仍在跑（费电、发热、还慢）。
  void cancelGeneration() {
    try {
      _engine?.cancelGeneration();
    } catch (e) {
      debugPrint('[LocalLlm] 取消失败: $e');
    }
  }

  /// 按需启用视觉投影（用户要发图片时调用）。
  ///
  /// 失败一律回退纯文本：先确保卸载残留投影，再返回 false——绝不允许
  /// "投影坏了导致连文本都不能用"。
  Future<bool> ensureVision() async {
    if (_visionAvailable) return true;
    final running = _visionLoadFuture;
    if (running != null) return running;
    final task = _ensureVisionInternal();
    _visionLoadFuture = task;
    try {
      return await task;
    } finally {
      if (identical(_visionLoadFuture, task)) _visionLoadFuture = null;
    }
  }

  Future<bool> _ensureVisionInternal() async {
    final engine = _engine;
    final projector = _pendingProjectorPath;
    if (engine == null ||
        projector == null ||
        !File(projector).existsSync() ||
        File(projector).lengthSync() <= 0 ||
        File('$projector.part').existsSync()) {
      return false;
    }
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

  /// 按下载时记录的主模型↔投影配对查找（最可靠：投影名常与模型名无关）。
  static Future<String?> _pairedProjector(String modelPath) async {
    try {
      final fileName = File(modelPath).uri.pathSegments.last;
      final projectorName = await ModelStorageSettings.projectorFor(fileName);
      if (projectorName == null || projectorName.isEmpty) return null;
      final dir = File(modelPath).parent;
      final candidate = File('${dir.path}/$projectorName');
      if (candidate.existsSync() &&
          candidate.lengthSync() > 0 &&
          !File('${candidate.path}.part').existsSync()) {
        return candidate.path;
      }
    } catch (_) {}
    return null;
  }

  /// 查找与主模型明确配对的视觉投影。
  ///
  /// mmproj 不是全局通用附件。没有下载时写入的配对记录就不自动挂载，
  /// 不能因为目录里只有一个文件、文件名相似或模型属于同一个集合就猜测。
  static String? _matchingProjector(String modelPath) {
    return null;
  }

  /// 非流式生成：发送消息列表，返回完整回复文本。
  Future<String> generate(
    List<LlamaChatMessage> messages, {
    int maxTokens = 1024,
    double temp = 0.8,
    double topP = 0.9,
  }) async {
    if (_disposed) throw StateError('引擎已释放');
    final previous = _generationQueue;
    final release = Completer<void>();
    _generationQueue = release.future;
    _generationBusy = true;
    try {
      await previous;
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
    } finally {
      _generationBusy = false;
      if (!release.isCompleted) release.complete();
    }
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
    if (_disposed) throw StateError('引擎已释放');
    final previous = _generationQueue;
    final release = Completer<void>();
    _generationQueue = release.future;
    _generationBusy = true;
    try {
      await previous;
      final engine = _engine;
      if (engine == null) throw StateError('模型未加载');
      // 只有认这个指令的家族（Qwen3 系）才追加 /no_think：别的模型会把它当
      // 可疑文本反复琢磨，导致思考打转（真机实测 Spark-X2.5 死循环）。
      final effectiveMessages =
          (suppressThinking && !thinkingEnabled && _supportsNoThink)
              ? _withNoThink(messages)
              : messages;
      // 投机解码：预构建原生库可能不含 llama-common 的投机包装层
      // （部分模型/上下文也不支持），此时引擎会直接抛错。策略：失败且
      // **尚未产出任何 token** 时关掉投机自动重试一次；仍失败才向上抛错。
      // 优化永远不许拖垮正常对话。
      var speculative =
          LocalLlmTuning.speculativeNgram && !_speculativeUnsupported;
      while (true) {
        var yielded = false;
        try {
          await for (final chunk in engine.create(
            effectiveMessages,
            // 关键：enableThinking 默认 true，模型会先把思考跑完再吐正文——
            // 用户看到的就是"不是流式、还慢"。关掉开关时必须真的传给模板。
            enableThinking: thinkingEnabled,
            params: GenerationParams(
              maxTokens: maxTokens,
              temp: temp,
              topP: topP,
              // 投机解码：n-gram 自推测（零额外内存；代码/HTML 这类重复多的输出收益大）。
              // 注意 API 形态：策略不在 GenerationParams 顶层，而是包在
              // speculativeDecodingConfig 里；null = 关闭。
              speculativeDecodingConfig: speculative
                  ? const SpeculativeDecodingConfig.ngramSimple()
                  : null,
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
              yielded = true;
              yield LocalLlmChunk(content: content, thinking: thinking);
            }
          }
          return;
        } catch (e) {
          if (speculative && !yielded) {
            debugPrint('[LocalLlm] 投机解码不可用，自动降级重试: $e');
            _speculativeUnsupported = true;
            speculative = false;
            continue;
          }
          rethrow;
        }
      }
    } finally {
      _generationBusy = false;
      if (!release.isCompleted) release.complete();
    }
  }

  /// 给最后一条用户消息追加 `/no_think`（Qwen3 系用于关闭思考的指令）。
  /// 只处理纯文本消息；已有该指令时不重复添加。
  static List<LlamaChatMessage> _withNoThink(List<LlamaChatMessage> messages) {
    if (messages.isEmpty) return messages;
    final result = List<LlamaChatMessage>.from(messages);
    final last = result.last;
    // 只处理纯文本消息（有图片等多模态内容时不动，避免破坏结构）。
    if (last.parts.length != 1 || last.parts.first is! LlamaTextContent) {
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
      _loadedKey = null;
      _visionAvailable = false;
      _projectorPath = null;
      _pendingProjectorPath = null;
      _visionLoadFuture = null;
      _projectorError = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelGeneration();
    // 在途加载必须等它走完（或失败）再卸载：loadModelSource 正在 Vulkan
    // 编译/读文件时直接 dispose 引擎句柄，native 层会崩——这是闪退的
    // 另一个来源（用户等不及退出页面就会触发）。等待本身无人依赖，
    // 不会阻塞 UI；加载完成后紧接着的 unload() 负责真正释放。
    final tail = _loadQueueTail;
    if (tail != null) {
      try {
        await tail;
      } catch (_) {}
    }
    try {
      await _generationQueue;
    } catch (_) {}
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
