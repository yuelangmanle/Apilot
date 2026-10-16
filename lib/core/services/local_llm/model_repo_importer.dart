import 'package:flutter/foundation.dart';

import 'community_model_service.dart';
import 'model_capabilities.dart';
import 'model_catalog.dart';
import 'model_catalog_store.dart';

class ModelRepoImporter {
  ModelRepoImporter._();

  static Future<String> importRepo(
    String repoOrUrl, {
    int? deviceRamMb,
  }) async {
    final target = parseTarget(repoOrUrl);
    if (target == null) {
      return '解析失败：请提供 HuggingFace / 魔搭 / GitHub 仓库链接或 owner/repo。未开始下载。';
    }
    final files = await resolve(target);
    return saveResolved(target, files, deviceRamMb: deviceRamMb);
  }

  static Future<List<ModelFileVariant>> resolve(RepoTarget target) async {
    final segments = target.path.split('/');
    return switch (target.host) {
      'modelscope' => CommunityModelService.resolveModelScopeRepo(target.path),
      'github' =>
        CommunityModelService.resolveGitHubRepo(segments[0], segments[1]),
      _ =>
        CommunityModelService.resolveHuggingFaceRepo(segments[0], segments[1]),
    };
  }

  static Future<String> saveResolved(
    RepoTarget target,
    List<ModelFileVariant> files, {
    int? deviceRamMb,
  }) async {
    if (files.isEmpty) {
      return '在 ${target.path}（${target.host}）没有找到可单文件运行的 GGUF。'
          '可能没有 GGUF、仅有分片，或文件 API 访问失败；不要猜测文件名。未开始下载。';
    }
    final mainFiles = files
        .where((file) => !ModelCapabilities.isProjectorFile(file.fileName))
        .toList();
    final projectors = files
        .where((file) => ModelCapabilities.isProjectorFile(file.fileName))
        .toList();
    if (mainFiles.isNotEmpty) {
      final recommended = CommunityModelService.pickVariant(mainFiles,
          deviceRamMb: deviceRamMb)!;
      await ModelCatalogStore().save(SavedModelEntry(
        info: LocalModelInfo(
          id: '${target.host}_${target.path}',
          name: target.path.split('/').last,
          description:
              '${target.host} · ${mainFiles.length} 个主模型文件 · ${projectors.length} 个视觉投影；下载前请选择文件',
          downloadUrl: recommended.downloadUrl,
          sizeBytes: recommended.sizeBytes,
          quantization: recommended.quantization,
          ramRequired: recommended.sizeBytes <= 0
              ? '未知'
              : '~${(recommended.sizeBytes * 1.35 / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
          tags: [target.host, if (projectors.isNotEmpty) '含投影待核对'],
          variants: mainFiles,
          projectors: projectors,
        ),
        source: 'ai',
        sourceUrl: target.original,
        addedAt: DateTime.now(),
      ));
    }
    final buffer = StringBuffer('已解析 ${target.path}。未开始下载，等待你选择具体文件。\n\n')
      ..writeln('| 文件名（file_name） | 类型 | 精度/量化 | 大小 |')
      ..writeln('| --- | --- | --- | --- |');
    for (final file in [...mainFiles, ...projectors]) {
      buffer.writeln('| ${file.fileName.replaceAll('|', '\\|')} | '
          '${ModelCapabilities.isProjectorFile(file.fileName) ? '视觉投影' : '主模型'} | '
          '${file.quantization} | ${file.sizeLabel} |');
    }
    buffer.writeln('\n主模型已保存在「我的社区模型」。请选择文件名再要求下载；'
        'F16/BF16/F32 通常需要更多内存。投影不自动下载或跨模型配对，必须核对模型架构、尺寸和发布者说明。');
    return buffer.toString();
  }

  static Future<SavedModelEntry?> savedRepo(String input) async {
    final target = parseTarget(input);
    if (target == null) return null;
    final id = '${target.host}_${target.path}';
    return (await ModelCatalogStore().list())
        .where((entry) => entry.info.id == id)
        .firstOrNull;
  }

  static RepoTarget? parseTarget(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[\w.\-]+/[\w.\-]+$').hasMatch(trimmed)) {
      return RepoTarget('huggingface', trimmed, trimmed);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
    final host = uri.host.toLowerCase();
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (['huggingface.co', 'www.huggingface.co', 'hf.co', 'hf-mirror.com']
        .contains(host)) {
      if (segments.length < 2) return null;
      return RepoTarget(
          'huggingface', '${segments[0]}/${segments[1]}', trimmed);
    }
    if ([
      'modelscope.cn',
      'www.modelscope.cn',
      'modelscope.ai',
      'www.modelscope.ai'
    ].contains(host)) {
      final index = segments.indexOf('models');
      if (index < 0 || index + 2 >= segments.length) return null;
      return RepoTarget('modelscope',
          '${segments[index + 1]}/${segments[index + 2]}', trimmed);
    }
    if (['github.com', 'www.github.com'].contains(host)) {
      if (segments.length < 2) return null;
      return RepoTarget(
          'github',
          '${segments[0]}/${segments[1].replaceFirst(RegExp(r'\.git$'), '')}',
          trimmed);
    }
    return null;
  }

  @visibleForTesting
  static String? hostForTest(String input) => parseTarget(input)?.host;

  @visibleForTesting
  static String? pathForTest(String input) => parseTarget(input)?.path;
}

class RepoTarget {
  final String host;
  final String path;
  final String original;

  const RepoTarget(this.host, this.path, this.original);
}
