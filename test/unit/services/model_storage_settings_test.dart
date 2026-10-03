import 'package:api_manager/core/services/local_llm/model_storage_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('同一个视觉投影不能同时归属多个主模型', () async {
    await ModelStorageSettings.pairProjector(
        'qwen-vl-2b-Q4.gguf', 'mmproj-qwen-vl-f16.gguf');

    final paired = await ModelStorageSettings.pairProjector(
        'qwen-vl-7b-Q4.gguf', 'mmproj-qwen-vl-f16.gguf');

    expect(paired, isFalse);
    expect(
      await ModelStorageSettings.projectorFor('qwen-vl-2b-Q4.gguf'),
      'mmproj-qwen-vl-f16.gguf',
    );
    expect(
      await ModelStorageSettings.projectorOwner('mmproj-qwen-vl-f16.gguf'),
      'qwen-vl-2b-Q4.gguf',
    );
  });

  test('更换主模型投影时释放旧投影归属', () async {
    await ModelStorageSettings.pairProjector('model.gguf', 'old-mmproj.gguf');
    final paired = await ModelStorageSettings.pairProjector(
        'model.gguf', 'new-mmproj.gguf');

    expect(paired, isTrue);
    expect(
        await ModelStorageSettings.projectorOwner('old-mmproj.gguf'), isNull);
    expect(await ModelStorageSettings.projectorFor('model.gguf'),
        'new-mmproj.gguf');
  });

  test('同一仓库的量化变体可显式共用投影', () async {
    expect(
      await ModelStorageSettings.pairProjector(
        'model-Q4.gguf',
        'repo__mmproj.gguf',
        shareGroup: 'owner/model',
      ),
      isTrue,
    );
    expect(
      await ModelStorageSettings.pairProjector(
        'model-Q5.gguf',
        'repo__mmproj.gguf',
        shareGroup: 'owner/model',
      ),
      isTrue,
    );
    expect(
      await ModelStorageSettings.pairProjector(
        'different-model.gguf',
        'repo__mmproj.gguf',
        shareGroup: 'another/model',
      ),
      isFalse,
    );
    expect(
      (await ModelStorageSettings.projectorPairs()).keys,
      containsAll(['model-Q4.gguf', 'model-Q5.gguf']),
    );
  });
}
