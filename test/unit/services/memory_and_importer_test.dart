import 'package:api_manager/core/services/ai/memory_store.dart';
import 'package:api_manager/core/services/local_llm/model_repo_importer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 长期记忆与"AI 找模型入库"的纯逻辑测试。
void main() {
  group('MemoryStore 分词与检索', () {
    test('中文按二元字组、英文按词', () {
      final tokens = MemoryStore.tokenize('我喜欢蓝色 blue sky');
      expect(tokens, contains('喜欢'));
      expect(tokens, contains('蓝色'));
      expect(tokens, contains('blue'));
      expect(tokens, contains('sky'));
    });

    test('相关记忆排序：命中关键词的排前面', () async {
      // 用纯函数验证打分逻辑（recall 依赖文件存储，这里直接比 tokenize 交集）。
      final query = MemoryStore.tokenize('我最喜欢什么颜色');
      final relevant = MemoryStore.tokenize('用户最喜欢的颜色是蓝色');
      final irrelevant = MemoryStore.tokenize('用户的电脑是 MacBook');
      int overlap(Set<String> a, Set<String> b) => a.where(b.contains).length;
      expect(overlap(query, relevant), greaterThan(overlap(query, irrelevant)));
    });

    test('"记住"启发式能提取内容', () {
      expect(MemoryStore.extractExplicitMemory('请记住：我最喜欢的颜色是蓝色'), '我最喜欢的颜色是蓝色');
      expect(MemoryStore.extractExplicitMemory('记住我的生日是 5 月 1 日'),
          '我的生日是 5 月 1 日');
      expect(MemoryStore.extractExplicitMemory('今天天气怎么样'), isNull);
      // 冒号后为空时不应误存。
      expect(MemoryStore.extractExplicitMemory('记住：'), isNull);
    });

    test('长期记忆拒绝明显的凭据格式', () {
      expect(
          MemoryStore.containsSensitiveData('api_key=sk-abcdef123456'), isTrue);
      expect(
          MemoryStore.containsSensitiveData('Bearer abcdef1234567890'), isTrue);
      expect(
        MemoryStore.extractExplicitMemory('记住：我的 API Key 是 sk-abcdef123456'),
        isNull,
      );
      expect(MemoryStore.containsSensitiveData('我喜欢蓝色'), isFalse);
    });
  });

  group('ModelRepoImporter 仓库解析', () {
    test('HuggingFace 链接 / hf-mirror / 裸 owner-repo', () {
      expect(
          ModelRepoImporter.hostForTest(
              'https://huggingface.co/XHToken/Spark-X2.5-4B-GGUF'),
          'huggingface');
      expect(
          ModelRepoImporter.pathForTest(
              'https://huggingface.co/XHToken/Spark-X2.5-4B-GGUF'),
          'XHToken/Spark-X2.5-4B-GGUF');
      expect(
          ModelRepoImporter.hostForTest(
              'https://hf-mirror.com/unsloth/Qwen3-1.7B-GGUF'),
          'huggingface');
      expect(ModelRepoImporter.hostForTest('unsloth/Qwen3-4B-GGUF'),
          'huggingface');
    });

    test('魔搭链接', () {
      expect(
          ModelRepoImporter.hostForTest(
              'https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
          'modelscope');
      expect(
          ModelRepoImporter.pathForTest(
              'https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
          'Qwen/Qwen2.5-1.5B-Instruct-GGUF');
    });

    test('GitHub 链接（含 .git 后缀）', () {
      expect(
          ModelRepoImporter.hostForTest(
              'https://github.com/XHToken/Spark-X2.5'),
          'github');
      expect(
          ModelRepoImporter.pathForTest(
              'https://github.com/XHToken/Spark-X2.5.git'),
          'XHToken/Spark-X2.5');
    });

    test('无关输入返回 null（不硬猜）', () {
      expect(ModelRepoImporter.hostForTest('你好'), isNull);
      expect(ModelRepoImporter.hostForTest('https://example.com/a/b'), isNull);
      expect(ModelRepoImporter.hostForTest(''), isNull);
    });
  });
}
