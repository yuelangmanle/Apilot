import 'package:api_manager/core/services/local_llm/community_model_service.dart';
import 'package:api_manager/core/services/local_llm/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// 社区模型服务：真实文件识别与版本推荐（纯函数，不发网络请求）。
void main() {
  group('quantizationFromFileName', () {
    test('识别常见量化后缀', () {
      expect(
          CommunityModelService.quantizationFromFileName(
              'Qwen3-1.7B-Q4_K_M.gguf'),
          'Q4_K_M');
      expect(
          CommunityModelService.quantizationFromFileName(
              'model-q4_k_s.gguf'),
          'Q4_K_S');
      expect(
          CommunityModelService.quantizationFromFileName(
              'model-IQ4_XS.gguf'),
          'IQ4_XS');
      expect(CommunityModelService.quantizationFromFileName('model-Q8_0.gguf'),
          'Q8_0');
      expect(CommunityModelService.quantizationFromFileName('model-Q2_K.gguf'),
          'Q2_K');
    });

    test('跳过未量化/全精度权重（体积过大）', () {
      expect(
          CommunityModelService.quantizationFromFileName(
              'model-BF16.gguf'),
          isNull);
      expect(
          CommunityModelService.quantizationFromFileName('model-f16.gguf'),
          isNull);
      expect(
          CommunityModelService.quantizationFromFileName('model-F32.gguf'),
          isNull);
    });

    test('跳过分片模型（App 内无法合并多文件）', () {
      expect(
          CommunityModelService.quantizationFromFileName(
              'model-Q4_K_M-00001-of-00002.gguf'),
          isNull);
    });

    test('非 gguf 文件不算候选', () {
      expect(CommunityModelService.quantizationFromFileName('README.md'),
          isNull);
      expect(
          CommunityModelService.quantizationFromFileName('config.json'),
          isNull);
    });
  });

  group('pickVariant', () {
    ModelFileVariant variant(String name, int sizeBytes) =>
        ModelFileVariant(
          fileName: name,
          downloadUrl: 'https://example.com/$name',
          sizeBytes: sizeBytes,
          quantization:
              CommunityModelService.quantizationFromFileName(name) ?? '?',
        );

    test('优先选 Q4_K_M（质量与体积平衡最好）', () {
      final variants = [
        variant('m-Q8_0.gguf', 4000000000),
        variant('m-Q4_K_M.gguf', 1500000000),
        variant('m-Q2_K.gguf', 700000000),
      ];
      expect(
          CommunityModelService.pickVariant(variants, deviceRamMb: 8192)!
              .quantization,
          'Q4_K_M');
    });

    test('内存不足时降级到装得下的版本', () {
      final variants = [
        variant('m-Q4_K_M.gguf', 3000000000),
        variant('m-Q2_K.gguf', 700000000),
      ];
      // 4GB 设备预算约 (4096-1500)*0.6 ≈ 1558MB → Q4_K_M(3GB) 装不下。
      expect(
          CommunityModelService.pickVariant(variants, deviceRamMb: 4096)!
              .quantization,
          'Q2_K');
    });

    test('全部装不下时取最小的（总比没有好）', () {
      final variants = [
        variant('m-Q4_K_M.gguf', 3000000000),
        variant('m-Q5_K_M.gguf', 3500000000),
      ];
      expect(
          CommunityModelService.pickVariant(variants, deviceRamMb: 2048)!
              .quantization,
          'Q4_K_M');
    });

    test('空列表返回 null', () {
      expect(CommunityModelService.pickVariant([]), isNull);
    });
  });

  group('ModelFileVariant 展示', () {
    test('大小格式化（MB/GB）', () {
      const small = ModelFileVariant(
          fileName: 'a.gguf',
          downloadUrl: 'u',
          sizeBytes: 524288000,
          quantization: 'Q4_K_M');
      const big = ModelFileVariant(
          fileName: 'b.gguf',
          downloadUrl: 'u',
          sizeBytes: 2147483648,
          quantization: 'Q4_K_M');
      expect(small.sizeLabel, '500 MB');
      expect(big.sizeLabel, '2.00 GB');
    });

    test('大小未知时如实说明，不显示 0 MB', () {
      const unknown = ModelFileVariant(
          fileName: 'a.gguf',
          downloadUrl: 'u',
          sizeBytes: 0,
          quantization: 'Q4_K_M');
      expect(unknown.sizeLabel, '大小未知');
    });
  });
}
