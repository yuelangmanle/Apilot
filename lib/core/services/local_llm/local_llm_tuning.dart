import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地推理性能档位。
enum LocalLlmPreset {
  /// 兼容：CPU 推理与小批量，最少依赖 GPU 驱动。
  saver('saver', '兼容（省内存）', 'CPU 推理、2 线程、小批量；最稳妥但速度较慢'),

  /// 默认安全档。llamadart 在 Android 上会把 auto 解析为 CPU，
  /// 这是库为避免不稳定 Vulkan 驱动而采取的兼容策略；这里显式保持 CPU，
  /// 避免 native 层 SIGSEGV/SIGABRT 直接杀进程。
  balanced('balanced', '均衡（推荐）', '安全 CPU 推理、4 线程、适中批量；优先保证不卡死和不闪退'),

  /// 只有用户明确选择时才打开 Vulkan，避免首次使用就触发设备驱动风险。
  performance('performance', 'GPU 加速（实验）', 'Vulkan 全量卸载；可能更快，但会发热、耗内存或受驱动影响');

  final String id;
  final String label;
  final String description;

  const LocalLlmPreset(this.id, this.label, this.description);

  static LocalLlmPreset fromId(String? id) => values.firstWhere(
        (p) => p.id == id,
        orElse: () => LocalLlmPreset.balanced,
      );
}

/// 本地推理调参：把 llama.cpp 的性能相关开关暴露成"三档预设 + 高级项"。
///
/// 依据（手机端实测经验）：预填充是算力受限，逐 token 生成是内存带宽受限；
/// KV cache 量化可以省内存，但部分 Vulkan/驱动组合会变慢或不稳定；GPU 卸载
/// 可能提速，但 Android native 驱动异常时会直接杀掉进程，所以默认必须保守。
class LocalLlmTuning {
  LocalLlmTuning._();

  static const _presetKey = 'llm_preset';
  static const _gpuLayersKey = 'llm_gpu_layers';
  static const _threadsKey = 'llm_threads';
  static const _flashKey = 'llm_flash_attention';
  static const _kvQuantKey = 'llm_kv_quantized';
  static const _speculativeKey = 'llm_speculative_ngram';
  static const _schemaKey = 'llm_tuning_schema';
  static const _schemaVersion = 3;

  static LocalLlmPreset _preset = LocalLlmPreset.balanced;
  static int? _gpuLayersOverride;
  static int? _threadsOverride;
  static bool _flashAttention = true;
  static bool _kvQuantized = false;

  /// 投机解码（n-gram 自推测）：**不需要草稿模型、不占额外内存**，
  /// 对"重复模式多"的输出（代码/HTML/表格）收益明显。
  static bool _speculativeNgram = false;

  static LocalLlmPreset get preset => _preset;
  static int? get gpuLayersOverride => _gpuLayersOverride;
  static int? get threadsOverride => _threadsOverride;
  static bool get flashAttention => _flashAttention;
  static bool get kvQuantized => _kvQuantized;
  static bool get speculativeNgram => _speculativeNgram;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schema = prefs.getInt(_schemaKey) ?? 0;
      if (schema < _schemaVersion) {
        _preset = LocalLlmPreset.balanced;
        _gpuLayersOverride = null;
        _threadsOverride = null;
        _flashAttention = true;
        _kvQuantized = false;
        _speculativeNgram = false;
        await prefs.setString(_presetKey, _preset.id);
        await prefs.remove(_gpuLayersKey);
        await prefs.remove(_threadsKey);
        await prefs.setBool(_flashKey, _flashAttention);
        await prefs.setBool(_kvQuantKey, _kvQuantized);
        await prefs.setBool(_speculativeKey, _speculativeNgram);
        await prefs.setInt(_schemaKey, _schemaVersion);
        return;
      }
      _preset = LocalLlmPreset.fromId(prefs.getString(_presetKey));
      _gpuLayersOverride = prefs.getInt(_gpuLayersKey);
      _threadsOverride = prefs.getInt(_threadsKey);
      _flashAttention = prefs.getBool(_flashKey) ?? true;
      _kvQuantized = prefs.getBool(_kvQuantKey) ?? false;
      _speculativeNgram = prefs.getBool(_speculativeKey) ?? false;
    } catch (e) {
      debugPrint('[Tuning] 读取失败: $e');
    }
  }

  static Future<void> setPreset(LocalLlmPreset preset) async {
    _preset = preset;
    _gpuLayersOverride = null;
    _threadsOverride = null;
    _flashAttention = true;
    // q8_0 只作为高级故障排查选项，不随性能档自动打开。
    _kvQuantized = false;
    _speculativeNgram = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_presetKey, preset.id);
      await prefs.setInt(_schemaKey, _schemaVersion);
      await prefs.remove(_gpuLayersKey);
      await prefs.remove(_threadsKey);
      await prefs.setBool(_flashKey, _flashAttention);
      await prefs.setBool(_kvQuantKey, _kvQuantized);
      await prefs.setBool(_speculativeKey, _speculativeNgram);
      await prefs.setInt(_schemaKey, _schemaVersion);
    } catch (_) {}
  }

  static Future<void> setAdvanced({
    int? gpuLayers,
    int? threads,
    bool? flashAttention,
    bool? kvQuantized,
    bool? speculativeNgram,
  }) async {
    // -1 = 自动（null）；0 = 强制纯 CPU；>0 = 指定层数。
    if (gpuLayers != null) {
      _gpuLayersOverride = gpuLayers < 0 ? null : gpuLayers;
    }
    if (threads != null) {
      _threadsOverride = threads <= 0 ? null : threads;
    }
    if (flashAttention != null) _flashAttention = flashAttention;
    if (kvQuantized != null) _kvQuantized = kvQuantized;
    if (speculativeNgram != null) _speculativeNgram = speculativeNgram;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_gpuLayersOverride == null) {
        await prefs.remove(_gpuLayersKey);
      } else {
        await prefs.setInt(_gpuLayersKey, _gpuLayersOverride!);
      }
      if (_threadsOverride == null) {
        await prefs.remove(_threadsKey);
      } else {
        await prefs.setInt(_threadsKey, _threadsOverride!);
      }
      await prefs.setBool(_flashKey, _flashAttention);
      await prefs.setBool(_kvQuantKey, _kvQuantized);
      await prefs.setBool(_speculativeKey, _speculativeNgram);
    } catch (_) {}
  }

  /// 生成用线程数：优先用户设置，否则按档位。
  /// 生成是内存带宽受限——大核 4 线程通常最优，省电档降到 2。
  static int resolveThreads() {
    if (_threadsOverride != null && _threadsOverride! > 0) {
      return _threadsOverride!;
    }
    return switch (_preset) {
      LocalLlmPreset.saver => 2,
      LocalLlmPreset.balanced => 4,
      LocalLlmPreset.performance => 6,
    };
  }

  /// null = 跟随档位；0 = 纯 CPU；>0 = 指定卸载层数。
  static int? resolveGpuLayers() {
    if (_gpuLayersOverride != null) return _gpuLayersOverride;
    return switch (_preset) {
      LocalLlmPreset.saver => 0,
      LocalLlmPreset.balanced => 0,
      LocalLlmPreset.performance => null,
    };
  }

  static int resolveBatchSize() => switch (_preset) {
        LocalLlmPreset.saver => 64,
        LocalLlmPreset.balanced => 128,
        LocalLlmPreset.performance => 256,
      };

  /// 推理后端。Android 默认使用 CPU 兼容路径；只有性能档或用户在高级项
  /// 明确指定了 GPU 层数时才请求 Vulkan。这样 GPU 是可选加速，不是启动风险。
  static GpuBackend resolveBackend() {
    if (Platform.isAndroid) {
      if (_gpuLayersOverride != null && _gpuLayersOverride! > 0) {
        return GpuBackend.vulkan;
      }
      return switch (_preset) {
        LocalLlmPreset.saver => GpuBackend.cpu,
        LocalLlmPreset.balanced => GpuBackend.cpu,
        LocalLlmPreset.performance => GpuBackend.vulkan,
      };
    }
    return GpuBackend.auto;
  }

  static FlashAttention resolveFlashAttention() {
    if (!_flashAttention) return FlashAttention.disabled;
    return FlashAttention.auto;
  }

  /// KV 量化：默认关闭（f16）。q8_0 省内存但需要 flash attention，且部分
  /// 机型/后端上会变慢；只允许用户在高级项中显式打开。
  static KvCacheType resolveKvCacheType() {
    if (!_kvQuantized) return KvCacheType.f16;
    return _flashAttention ? KvCacheType.q8_0 : KvCacheType.f16;
  }

  static String describe() {
    final parts = <String>[
      _preset.label,
      '线程 ${resolveThreads() == 0 ? '自动' : resolveThreads()}',
      'GPU ${resolveBackend() == GpuBackend.cpu ? '关(CPU)' : resolveBackend().name}'
          '${resolveGpuLayers() == null ? '' : '/${resolveGpuLayers()}层'}',
      '批量 ${resolveBatchSize()}',
      _flashAttention ? 'FlashAttn 开' : 'FlashAttn 关',
      _kvQuantized ? 'KV q8_0' : 'KV f16',
      if (_speculativeNgram) '投机 n-gram',
    ];
    return parts.join(' · ');
  }
}
