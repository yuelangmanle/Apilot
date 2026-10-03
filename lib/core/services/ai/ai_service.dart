import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api_config.dart';
import '../api_service.dart';
import '../local_llm/local_llm_engine.dart';
import '../local_llm/model_download_service.dart';

/// AI 功能统一入口：按"AI 设置"选择的后端（云端配置 / 本地模型）执行任务。
///
/// 设计原则：
/// - 不发送 API Key 给 AI——只发送任务相关上下文；
/// - 未配置来源时返回 null，调用方回退到本地启发式；
/// - 全程超时保护（30 秒）。
class AiService {
  AiService._();

  static const String _sourceKey = 'apilot_ai_source';
  static const String _useLocalKey = 'apilot_ai_use_local';
  static const String _enabledKey = 'apilot_ai_enabled';
  static const String _localModelKey = 'apilot_ai_local_model';
  // 工具模式要带工具说明 + 可能 2048 输出，30 秒经常不够（尤其国内中转站）。
  static const Duration _timeout = Duration(seconds: 90);

  /// 最近一次失败的原因（界面据此给出可读提示，而不是笼统的"调用失败"）。
  static String? lastError;

  /// 已加载的本地引擎共享给全部 AI 功能：
  /// 聊天页加载模型后注册到这里，AI 诊断/分析等无需重复加载。
  static LocalLlmEngine? _sharedEngine;

  static void registerLocalEngine(LocalLlmEngine? engine) {
    _sharedEngine = engine;
  }

  static LocalLlmEngine? get sharedLocalEngine =>
      (_sharedEngine?.isLoaded ?? false) ? _sharedEngine : null;

  /// 当前来源是否选择了本地模型（AgentRunner 决定推理路径用）。
  static Future<bool> isLocalSourceSelected() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_useLocalKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// AI 功能是否启用。
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 当前选中的来源描述（用于界面展示）。
  static Future<String> sourceDescription(List<ApiConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_useLocalKey) ?? false) {
        final engine = sharedLocalEngine;
        return engine == null
            ? '本地模型（未加载：先在模型商店下载并打开对话）'
            : '本地模型 · ${engine.loadedModelPath?.split('/').last ?? ''}';
      }
      final id = prefs.getString(_sourceKey);
      if (id == null || id.isEmpty) return '未配置';
      for (final config in configs) {
        if (config.id == id) return config.name;
      }
      return '未配置';
    } catch (_) {
      return '未配置';
    }
  }

  /// 执行一次 AI 问答。返回 null 表示未配置、未启用或调用失败。
  static Future<String?> ask({
    required String userPrompt,
    String? systemPrompt,
    required List<ApiConfig> configs,
    LocalLlmEngine? localEngine,
    /// 流式增量回调（云端工具模式用它显示进度）。
    void Function(String delta)? onDelta,
    /// 指定用哪个配置（云端对话页传自己的配置，不看全局设置）。
    ApiConfig? preferredConfig,
    int maxTokens = 512,
  }) async {
    // 只有"按全局设置挑来源"时才看总开关；调用方显式给了配置或引擎
    // （云端对话页/本地对话页）就必须照做——否则用户在对话里怎么点都会
    // 收到"AI 未配置、调用失败或没有返回内容"。
    final explicitlyRouted = preferredConfig != null ||
        (localEngine != null && localEngine.isLoaded);
    if (!explicitlyRouted && !await isEnabled()) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final useLocal = prefs.getBool(_useLocalKey) ?? false;

      if (useLocal) {
        final engine = localEngine ?? sharedLocalEngine;
        if (engine == null || !engine.isLoaded) {
          // 没有已加载的引擎：尝试自动加载本机已下载的最小模型，
          // 否则"AI 设置里选本地模型"会静默失效。
          final auto = await _tryAutoLoadLocalEngine();
          if (auto == null) return null;
          return await _askLocal(auto, userPrompt, systemPrompt, maxTokens)
              .timeout(const Duration(minutes: 3));
        }
        return await _askLocal(engine, userPrompt, systemPrompt, maxTokens)
            .timeout(const Duration(minutes: 3));
      }

      // ① 对话自己指定的配置优先（云端对话页）；
      // ② 否则按全局"AI 设置"里的来源。
      var config = preferredConfig;
      if (config == null) {
        final configId = prefs.getString(_sourceKey);
        if (configId == null || configId.isEmpty) return null;
        for (final candidate in configs) {
          if (candidate.id == configId) {
            config = candidate;
            break;
          }
        }
      }
      if (config == null) return null;

      return await _askCloud(config, userPrompt, systemPrompt, maxTokens,
              onDelta: onDelta)
          .timeout(_timeout);
    } on TimeoutException {
      lastError = '请求超时（${_timeout.inSeconds}s）：模型/中转站太慢或网络不通';
      return null;
    } catch (e) {
      lastError = '$e';
      debugPrint('[AiService] ask 失败: $e');
      return null;
    }
  }

  static Future<String?> _askCloud(
    ApiConfig config,
    String userPrompt,
    String? systemPrompt,
    int maxTokens, {
    void Function(String delta)? onDelta,
  }) async {
    final model = config.selectedModel ??
        (config.models.isEmpty ? '' : config.models.first);
    if (model.isEmpty) return null;

    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    // 走流式：文本边到边显示（onDelta），且失败马上暴露——
    // 之前用非流式 sendRequest，遇到慢中转站会一直转圈、停止按钮也没用。
    final buffer = StringBuffer();
    Object? streamError;
    try {
      await for (final event in ApiService().sendRequestStream(
        apiConfig: config,
        model: model,
        requestBody: {
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': 0.3,
        },
      )) {
        if (event.delta != null && event.delta!.isNotEmpty) {
          buffer.write(event.delta);
          onDelta?.call(event.delta!);
        }
        if (event.isDone && event.response != null) {
          final text = extractAssistantText(event.response!['body']);
          if (text != null && text.isNotEmpty) return text;
        }
      }
    } catch (e) {
      streamError = e;
    }
    if (buffer.isNotEmpty) return buffer.toString();
    // 流式不可用（部分中转站不接受 stream / stream_options）→ 回退非流式，
    // 否则用户会看到"AI 未配置、调用失败"，而其实只是协议差异。
    debugPrint('[AiService] 云端流式失败，回退非流式: $streamError');
    try {
      final result = await ApiService().sendRequest(
        apiConfig: config,
        model: model,
        endpoint: '',
        requestBody: {
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': 0.3,
        },
      );
      final text = extractAssistantText(result['body']);
      if (text != null && text.isNotEmpty) return text;
      lastError = '模型返回了空内容（非流式回退也没拿到文本）';
    } catch (e) {
      lastError = '$e';
      debugPrint('[AiService] 云端非流式也失败: $e');
    }
    return null;
  }

  static Future<String?> _askLocal(
    LocalLlmEngine engine,
    String userPrompt,
    String? systemPrompt,
    int maxTokens,
  ) async {
    final messages = <LlamaChatMessage>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        LlamaChatMessage.fromText(
            role: LlamaChatRole.system, text: systemPrompt),
      LlamaChatMessage.fromText(
          role: LlamaChatRole.user, text: userPrompt),
    ];
    final text = await engine.generate(messages, maxTokens: maxTokens);
    return text.isEmpty ? null : text;
  }

  /// 自动加载本机已下载的模型（优先最小的，加载最快）。
  /// 加载成功的引擎会注册为共享引擎，后续 AI 调用直接复用。
  /// 用户在「AI 设置」里指定的本地模型（重启后仍生效）。
  static Future<void> setPreferredLocalModel(String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localModelKey, filePath);
      // 立刻换掉共享引擎，让下一次调用就用新模型。
      final previous = _sharedEngine;
      _sharedEngine = null;
      await previous?.dispose();
    } catch (e) {
      debugPrint('[AiService] 保存本地模型选择失败: $e');
    }
  }

  static Future<LocalLlmEngine?> _tryAutoLoadLocalEngine() async {
    try {
      final files = await ModelDownloadService.listDownloadedModels();
      if (files.isEmpty) return null;
      // 优先用户指定的模型；否则最小的那个（加载最快）。
      String? preferred;
      try {
        final prefs = await SharedPreferences.getInstance();
        preferred = prefs.getString(_localModelKey);
      } catch (_) {}
      File? target;
      if (preferred != null && preferred.isNotEmpty) {
        for (final file in files) {
          if (file.path == preferred) {
            target = file;
            break;
          }
        }
      }
      target ??= (files
            ..sort((a, b) => a.lengthSync().compareTo(b.lengthSync())))
          .first;
      final engine = LocalLlmEngine();
      await engine.loadModel(target.path);
      _sharedEngine = engine;
      return engine;
    } catch (_) {
      return null;
    }
  }

  /// 从响应体中提取助手文本（兼容 OpenAI 与 Anthropic 两种形状）。
  static String? extractAssistantText(Object? body) {
    if (body is! Map) return null;
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
      }
    }
    final content = body['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map && first['text'] is String) {
        return first['text'] as String;
      }
    }
    return null;
  }
}
