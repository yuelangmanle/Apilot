import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地推理性能档位。
enum LocalLlmPreset {
  /// 省电：少线程、关 GPU、KV 量化到 4bit（内存最省）。
  saver('saver', '省电（更慢）', '线程少、GPU 关、KV 压到最小：最省电省内存，但生成最慢'),

  /// 均衡（默认）：大核 4 线程 + 自动 GPU 卸载 + q8_0 KV 量化。
  balanced('balanced', '均衡（推荐）', '大核 4 线程 + KV q8_0：速度与发热的平衡点，日常用这个'),

  /// 性能：全大核 + 尽量 GPU 卸载 + f16 KV（最快，发热明显）。
  performance('performance', '性能（最快）', '全大核 + 尽量 GPU 卸载：生成最快，但更热更耗电，个别机型可能不稳');

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
/// 依据（手机端实测经验）：预填充是算力受限（线程越多越好），逐 token 生成是
/// 内存带宽受限（超过 2-4 个大核反而更慢）；KV cache 量化省 30-50% 内存；
/// GPU 卸载能到 1.5-2 倍，但机型差异大，所以默认"自动"、性能档才激进。
class LocalLlmTuning {
  LocalLlmTuning._();

  static const _presetKey = 'llm_preset';
  static const _gpuLayersKey = 'llm_gpu_layers';
  static const _threadsKey = 'llm_threads';
  static const _flashKey = 'llm_flash_attention';
  static const _kvQuantKey = 'llm_kv_quantized';

  static LocalLlmPreset _preset = LocalLlmPreset.balanced;
  static int? _gpuLayersOverride;
  static int? _threadsOverride;
  static bool _flashAttention = true;
  static bool _kvQuantized = true;

  static LocalLlmPreset get preset => _preset;
  static int? get gpuLayersOverride => _gpuLayersOverride;
  static int? get threadsOverride => _threadsOverride;
  static bool get flashAttention => _flashAttention;
  static bool get kvQuantized => _kvQuantized;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preset = LocalLlmPreset.fromId(prefs.getString(_presetKey));
      _gpuLayersOverride = prefs.getInt(_gpuLayersKey);
      _threadsOverride = prefs.getInt(_threadsKey);
      _flashAttention = prefs.getBool(_flashKey) ?? true;
      _kvQuantized = prefs.getBool(_kvQuantKey) ?? true;
    } catch (e) {
      debugPrint('[Tuning] 读取失败: $e');
    }
  }

  static Future<void> setPreset(LocalLlmPreset preset) async {
    _preset = preset;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_presetKey, preset.id);
    } catch (_) {}
  }

  static Future<void> setAdvanced({
    int? gpuLayers,
    int? threads,
    bool? flashAttention,
    bool? kvQuantized,
  }) async {
    if (gpuLayers != null) _gpuLayersOverride = gpuLayers == 0 ? null : gpuLayers;
    if (threads != null) _threadsOverride = threads == 0 ? null : threads;
    if (flashAttention != null) _flashAttention = flashAttention;
    if (kvQuantized != null) _kvQuantized = kvQuantized;
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
    } catch (_) {}
  }

  /// 生成用线程数：优先用户设置，否则按档位。
  /// 生成是内存带宽受限——大核 4 线程通常最优，省电档降到 2。
  static int resolveThreads() {
    if (_threadsOverride != null && _threadsOverride! > 0) {
      return _threadsOverride!;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return switch (_preset) {
        LocalLlmPreset.saver => 2,
        LocalLlmPreset.balanced => 4,
        LocalLlmPreset.performance => 6,
      };
    }
    return 0; // 桌面交给 llama.cpp 自动
  }

  /// GPU 卸载层数：0 = 不卸载；负值 = 让底层自动。
  static int resolveGpuLayers() {
    if (_gpuLayersOverride != null) return _gpuLayersOverride!;
    return switch (_preset) {
      LocalLlmPreset.saver => 0,
      LocalLlmPreset.balanced => 0, // 均衡档保守：GPU 在部分机型不稳
      LocalLlmPreset.performance => -1, // -1 = 尽量全部卸载（依赖底层解释）
    };
  }

  static FlashAttention resolveFlashAttention() {
    if (!_flashAttention) return FlashAttention.disabled;
    return FlashAttention.auto;
  }

  /// KV 量化：q8_0 省一半内存，几乎不掉质量（要求 flash attention 打开）。
  static KvCacheType resolveKvCacheType() {
    if (!_kvQuantized) return KvCacheType.f16;
    return _flashAttention ? KvCacheType.q8_0 : KvCacheType.f16;
  }

  static String describe() {
    final parts = <String>[
      _preset.label,
      '线程 ${resolveThreads() == 0 ? '自动' : resolveThreads()}',
      'GPU 层 ${resolveGpuLayers() == 0 ? '关' : (resolveGpuLayers() < 0 ? '自动' : resolveGpuLayers())}',
      _flashAttention ? 'FlashAttn 开' : 'FlashAttn 关',
      _kvQuantized ? 'KV q8_0' : 'KV f16',
    ];
    return parts.join(' · ');
  }
}
