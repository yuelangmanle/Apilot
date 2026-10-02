import 'package:flutter/foundation.dart';

import 'community_model_service.dart';
import 'model_capabilities.dart';
import 'model_catalog.dart';
import 'model_catalog_store.dart';

/// 把一个模型仓库（HuggingFace / 魔搭 / GitHub 链接或 owner/repo）
/// 解析成可下载条目，写进「我的社区模型」；可选立即开始下载。
///
/// 这是"让 AI 自己上网找模型 → 入库 → 下载"这条链路的落地点：
/// 解析一律用真实 API（文件清单与体积），绝不猜文件名。
class ModelRepoImporter {
  ModelRepoImporter._();

  /// 下载回调：由界面层注入（复用模型商店的下载服务，保证进度统一）。
  static Future<void> Function(String url, String fileName)? onDownload;

  /// 返回给 AI 的可读结果。
  static Future<String> importRepo(
    String repoOrUrl, {
    int? deviceRamMb,
    bool download = false,
  }) async {
    final target = parseTarget(repoOrUrl);
    if (target == null) {
      return '解析失败：请给 HuggingFace / 魔搭 / GitHub 的仓库链接，'
          '或 owner/repo 形式（例如 XHToken/Spark-X2.5-4B-GGUF）。';
    }

    List<ModelFileVariant> files;
    switch (target.host) {
      case 'modelscope':
        files = await CommunityModelService.resolveModelScopeRepo(target.path);
        break;
      case 'github':
        final segments = target.path.split('/');
        files = segments.length >= 2
            ? await CommunityModelService.resolveGitHubRepo(
                segments[0], segments.sublist(1).join('/'))
            : const [];
        break;
      default:
        final segments = target.path.split('/');
        files = segments.length >= 2
            ? await CommunityModelService.resolveHuggingFaceRepo(
                segments[0], segments.sublist(1).join('/'))
            : const [];
    }

    if (files.isEmpty) {
      return '在 ${target.path}（${target.host}）里没有找到可直接下载的 GGUF 文件：'
          '可能是仓库不含 GGUF、只有分片、或该平台限流。可以换一个仓库再试。';
    }

    final mainFiles = files
        .where((f) => !ModelCapabilities.isProjectorFile(f.fileName))
        .toList();
    if (mainFiles.isEmpty) {
      return '${target.path} 里只有视觉投影文件（mmproj），没有主模型文件。';
    }
    final projector = files
        .where((f) => ModelCapabilities.isProjectorFile(f.fileName))
        .firstOrNull;
    final recommended =
        CommunityModelService.pickVariant(mainFiles, deviceRamMb: deviceRamMb) ??
            mainFiles.first;
    final name = target.path.split('/').last;
    final totalGb = (recommended.sizeBytes + (projector?.sizeBytes ?? 0)) /
        (1024 * 1024 * 1024);

    final info = LocalModelInfo(
      id: '${target.host}_${target.path}',
      name: name,
      description: 'AI 找到并入库（${target.host}）· ${mainFiles.length} 个版本可选'
          '${projector != null ? ' · 含视觉投影（可看图）' : ''}',
      downloadUrl: recommended.downloadUrl,
      sizeBytes: recommended.sizeBytes,
      quantization: recommended.quantization,
      ramRequired: totalGb > 0
          ? '~${(totalGb * 1.35).toStringAsFixed(1)} GB'
          : '—',
      tags: [
        switch (target.host) {
          'modelscope' => 'ModelScope',
          'github' => 'GitHub',
          _ => 'HuggingFace',
        },
        if (projector != null) '多模态',
        if (ModelCapabilities.supportsThinking(name)) '可深度思考',
      ],
      variants: mainFiles,
      mmProjUrl: projector?.downloadUrl,
    );

    await ModelCatalogStore().save(SavedModelEntry(
      info: info,
      source: 'ai',
      sourceUrl: target.original,
      addedAt: DateTime.now(),
    ));

    var message = '已入库「$name」到「我的社区模型」：'
        '默认 ${recommended.quantization}（${recommended.sizeMb}'
        '${projector != null ? ' + 视觉投影 ${projector.sizeLabel}' : ''}），'
        '共 ${mainFiles.length} 个版本可在模型商店里选择。';

    if (download) {
      final onDownload = ModelRepoImporter.onDownload;
      if (onDownload == null) {
        message += '（当前入口没有接入下载，请到模型商店点下载）';
      } else {
        await onDownload(recommended.downloadUrl, recommended.fileName);
        if (projector != null) {
          await onDownload(projector.downloadUrl, projector.fileName);
        }
        message += ' 已开始下载'
            '${projector != null ? '（主模型 + 视觉投影）' : ''}，'
            '可在「下载管理」里看进度。';
      }
    }
    return message;
  }

  /// 解析仓库坐标：链接或 owner/repo。
  static RepoTarget? parseTarget(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      final host = uri.host.toLowerCase();
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (host.contains('huggingface.co') || host.contains('hf-mirror.com')) {
        if (segments.length < 2) return null;
        return RepoTarget('huggingface', '${segments[0]}/${segments[1]}', trimmed);
      }
      if (host.contains('modelscope.cn')) {
        final idx = segments.indexOf('models');
        if (idx < 0 || idx + 2 >= segments.length) return null;
        return RepoTarget(
            'modelscope', '${segments[idx + 1]}/${segments[idx + 2]}', trimmed);
      }
      if (host.contains('github.com')) {
        if (segments.length < 2) return null;
        final repo = segments[1].replaceAll(RegExp(r'\.git$'), '');
        return RepoTarget('github', '${segments[0]}/$repo', trimmed);
      }
      return null;
    }

    if (RegExp(r'^[\w.\-]+/[\w.\-]+$').hasMatch(trimmed)) {
      // 裸 owner/repo：默认 HuggingFace（最常见）。
      return RepoTarget('huggingface', trimmed, trimmed);
    }
    return null;
  }

  @visibleForTesting
  static String? hostForTest(String input) => parseTarget(input)?.host;

  @visibleForTesting
  static String? pathForTest(String input) => parseTarget(input)?.path;
}

/// 解析出的仓库坐标。
class RepoTarget {
  final String host; // huggingface / modelscope / github
  final String path; // owner/repo
  final String original;

  const RepoTarget(this.host, this.path, this.original);
}
