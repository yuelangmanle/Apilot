import 'dart:io';

import 'package:api_manager/core/services/local_llm/model_catalog.dart';
import 'package:api_manager/core/services/local_llm/model_catalog_store.dart';
import 'package:api_manager/features/local_llm/services/model_curator_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ModelCatalogStore', () {
    late Directory dir;
    late ModelCatalogStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('catalog_store_test');
      store = ModelCatalogStore(overrideDir: dir);
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    SavedModelEntry entry(String id, {String source = 'ai'}) => SavedModelEntry(
          info: LocalModelInfo(
            id: id,
            name: 'Model $id',
            description: '介绍 $id',
            downloadUrl: 'https://example.com/$id.gguf',
            sizeBytes: 1000000,
            quantization: 'Q4_K_M',
            ramRequired: '~1 GB',
            tags: const ['中文'],
          ),
          source: source,
          addedAt: DateTime.now(),
        );

    test('save then list round-trips entries', () async {
      await store.save(entry('a'));
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.first.info.name, 'Model a');
      expect(list.first.info.description, '介绍 a');
      expect(list.first.source, 'ai');
    });

    test('saveAll dedupes by id and keeps newest first', () async {
      await store.saveAll([entry('a'), entry('b')]);
      await store.saveAll([entry('c'), entry('a')]);
      final list = await store.list();
      expect(list.map((e) => e.info.id).toSet(), {'a', 'b', 'c'});
      expect(list, hasLength(3));
    });

    test('delete removes the entry', () async {
      await store.save(entry('a'));
      await store.delete('a');
      expect(await store.list(), isEmpty);
      expect(await store.contains('a'), isFalse);
    });

    test('survives corrupted file without throwing', () async {
      final file =
          File(p.join(dir.path, 'model_catalog', 'saved_models.json'));
      file.parent.createSync(recursive: true);
      await file.writeAsString('{ not json');
      expect(await store.list(), isEmpty);
      // 损坏后仍能正常写入。
      await store.save(entry('a'));
      expect(await store.list(), hasLength(1));
    });

    test('variants and projector URL survive persistence', () async {
      final withExtras = SavedModelEntry(
        info: const LocalModelInfo(
          id: 'vision',
          name: 'Vision',
          description: '多模态',
          downloadUrl: 'https://example.com/v.gguf',
          sizeBytes: 2000000,
          quantization: 'Q4_K_M',
          ramRequired: '~2 GB',
          mmProjUrl: 'https://example.com/mmproj-f16.gguf',
          variants: [
            ModelFileVariant(
              fileName: 'v-Q4_K_M.gguf',
              downloadUrl: 'https://example.com/v-Q4_K_M.gguf',
              sizeBytes: 2000000,
              quantization: 'Q4_K_M',
            ),
          ],
        ),
        source: 'paste',
        addedAt: DateTime.now(),
      );
      await store.save(withExtras);
      final loaded = (await store.list()).single;
      expect(loaded.info.mmProjUrl, 'https://example.com/mmproj-f16.gguf');
      expect(loaded.info.variants, hasLength(1));
      expect(loaded.info.variants.first.quantization, 'Q4_K_M');
    });
  });

  group('ModelCuratorService.extractRepositories', () {
    test('提取 HuggingFace 仓库链接', () {
      final refs = ModelCuratorService.extractRepositories(
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF');
      expect(refs, hasLength(1));
      expect(refs.first.host, 'huggingface');
      expect(refs.first.path, 'unsloth/Qwen3-4B-GGUF');
    });

    test('提取魔搭仓库链接', () {
      final refs = ModelCuratorService.extractRepositories(
          'https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF');
      expect(refs, hasLength(1));
      expect(refs.first.host, 'modelscope');
      expect(refs.first.path, 'Qwen/Qwen2.5-1.5B-Instruct-GGUF');
    });

    test('多行粘贴 → 多个仓库且去重', () {
      final refs = ModelCuratorService.extractRepositories('''
https://huggingface.co/a/b-GGUF
https://hf-mirror.com/a/b-GGUF
https://huggingface.co/c/d-GGUF/tree/main
https://modelscope.cn/models/e/f-GGUF
''');
      expect(refs, hasLength(3));
      expect(refs.map((r) => r.path).toList(),
          containsAll(['a/b-GGUF', 'c/d-GGUF', 'e/f-GGUF']));
    });

    test('裸 owner/repo 坐标也识别', () {
      final refs = ModelCuratorService.extractRepositories(
          'unsloth/Qwen3-1.7B-GGUF\nbartowski/Llama-3.2-3B-Instruct-GGUF');
      expect(refs, hasLength(2));
      expect(refs.first.path, 'unsloth/Qwen3-1.7B-GGUF');
    });

    test('tree/resolve 子路径归一化到仓库根', () {
      final refs = ModelCuratorService.extractRepositories(
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/tree/main');
      expect(refs.single.path, 'unsloth/Qwen3-4B-GGUF');
    });

    test('非仓库文本不误判', () {
      expect(ModelCuratorService.extractRepositories('你好，帮我看看这个'),
          isEmpty);
      expect(
          ModelCuratorService.extractRepositories(
              'https://example.com/not/a/repo'),
          isEmpty);
    });
  });

  group('内置目录', () {
    test('包含多模态与推理模型，且都有真实下载地址', () {
      const builtin = LocalModelCatalog.builtin;
      expect(builtin.length, greaterThanOrEqualTo(8));
      for (final model in builtin) {
        expect(model.downloadUrl, startsWith('https://'));
        expect(model.sizeBytes, greaterThan(0),
            reason: '${model.name} 必须有真实体积（不要显示 0 MB）');
      }
      expect(builtin.any((m) => m.mmProjUrl != null), isTrue,
          reason: '至少有一个多模态模型带视觉投影地址');
      expect(builtin.any((m) => m.tags.contains('可深度思考')), isTrue);
    });
  });
}
