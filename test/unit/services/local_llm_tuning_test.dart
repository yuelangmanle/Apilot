import 'package:api_manager/core/services/local_llm/local_llm_tuning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalLlmTuning.setPreset(LocalLlmPreset.balanced);
  });

  tearDown(() async {
    await LocalLlmTuning.setPreset(LocalLlmPreset.balanced);
  });

  test('默认均衡档保持移动端安全边界', () {
    expect(LocalLlmTuning.preset, LocalLlmPreset.balanced);
    expect(LocalLlmTuning.resolveGpuLayers(), 0);
    expect(LocalLlmTuning.resolveBatchSize(), 128);
    expect(LocalLlmTuning.resolveThreads(), inInclusiveRange(1, 8));
    expect(LocalLlmTuning.kvQuantized, isFalse);
    expect(LocalLlmTuning.speculativeNgram, isFalse);
  });

  test('GPU 实验档使用保守卸载和批量，不再全量塞入显存', () async {
    await LocalLlmTuning.setPreset(LocalLlmPreset.performance);

    expect(LocalLlmTuning.resolveGpuLayers(), 16);
    expect(LocalLlmTuning.resolveBatchSize(), 128);
    expect(LocalLlmTuning.diagnostics(), containsPair('backend', isNotNull));
  });

  test('高级参数会被硬限制，并保持后端与 GPU 层数一致', () async {
    await LocalLlmTuning.setAdvanced(gpuLayers: 999, threads: 999);

    expect(LocalLlmTuning.gpuLayersOverride, 64);
    expect(LocalLlmTuning.threadsOverride, 8);
    expect(LocalLlmTuning.resolveGpuLayers(), 64);
    expect(LocalLlmTuning.resolveThreads(), 8);

    await LocalLlmTuning.setAdvanced(gpuLayers: 0, threads: 1);
    expect(LocalLlmTuning.resolveGpuLayers(), 0);
    expect(LocalLlmTuning.resolveThreads(), 1);
    expect(
        LocalLlmTuning.diagnostics(),
        allOf([
          containsPair('gpuLayers', 0),
          containsPair('threads', 1),
          containsPair('batchSize', 128),
        ]));
  });

  test('自动值会清除手动覆盖，诊断信息可序列化', () async {
    await LocalLlmTuning.setAdvanced(
      gpuLayers: 24,
      threads: 6,
      flashAttention: false,
      kvQuantized: true,
      speculativeNgram: true,
    );
    await LocalLlmTuning.setAdvanced(gpuLayers: -1, threads: 0);

    final diagnostics = LocalLlmTuning.diagnostics();
    expect(LocalLlmTuning.gpuLayersOverride, isNull);
    expect(LocalLlmTuning.threadsOverride, isNull);
    expect(diagnostics['gpuLayersOverride'], isNull);
    expect(diagnostics['threadsOverride'], isNull);
    expect(diagnostics['flashAttention'], isFalse);
    expect(diagnostics['kvCache'], 'f16');
    expect(diagnostics['speculativeNgram'], isTrue);
  });
}
