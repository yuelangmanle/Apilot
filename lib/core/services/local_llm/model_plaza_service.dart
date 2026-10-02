import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'community_model_service.dart';
import 'model_capabilities.dart';
import 'model_catalog.dart';

/// 模型广场的筛选条件。
class PlazaFilter {
  /// 关键词（模型名/作者）。
  final String query;

  /// 只看能看图的（仓库含视觉投影 mmproj）。
  final bool visionOnly;

  /// 只看支持深度思考的家族。
  final bool thinkingOnly;

  /// 只看中文模型（名字含 qwen/glm/deepseek/yi/minicpm/baichuan 等）。
  final bool chineseOnly;

  /// 体积上限（GB），0 = 不限（按设备内存给默认值）。
  final double maxSizeGb;

  /// 排序：downloads / likes / recent / size
  final String sort;

  /// 来源：huggingface / modelscope / all
  final String source;

  const PlazaFilter({
    this.query = 'gguf',
    this.visionOnly = false,
    this.thinkingOnly = false,
    this.chineseOnly = false,
    this.maxSizeGb = 0,
    this.sort = 'downloads',
    this.source = 'all',
  });

  PlazaFilter copyWith({
    String? query,
    bool? visionOnly,
    bool? thinkingOnly,
    bool? chineseOnly,
    double? maxSizeGb,
    String? sort,
    String? source,
  }) =>
      PlazaFilter(
        query: query ?? this.query,
        visionOnly: visionOnly ?? this.visionOnly,
        thinkingOnly: thinkingOnly ?? this.thinkingOnly,
        chineseOnly: chineseOnly ?? this.chineseOnly,
        maxSizeGb: maxSizeGb ?? this.maxSizeGb,
        sort: sort ?? this.sort,
        source: source ?? this.source,
      );
}

/// 一个模型在广场里的完整条目（含能力标签与投影信息）。
class PlazaModel {
  final LocalModelInfo info;

  /// 是否视觉模型（**硬事实**：仓库里有 mmproj 文件）。
  final bool hasProjector;

  /// 视觉投影文件（可空）。
  final ModelFileVariant? projector;

  /// 支持深度思考（家族判断）。
  final bool supportsThinking;

  final int downloads;
  final int likes;
  final String sourceLabel;

  const PlazaModel({
    required this.info,
    required this.hasProjector,
    this.projector,
    required this.supportsThinking,
    this.downloads = 0,
    this.likes = 0,
    required this.sourceLabel,
  });

  /// 主模型 + 投影的总大小（GB）。
  double get bundleSizeGb {
    final main = info.sizeBytes;
    final proj = projector?.sizeBytes ?? 0;
    return (main + proj) / (1024 * 1024 * 1024);
  }

  List<String> get capabilityTags => [
        if (hasProjector) '看图',
        if (supportsThinking) '深度思考',
        if (_isChinese(info.name)) '中文',
      ];

  static bool _isChinese(String name) {
    final lower = name.toLowerCase();
    return const ['qwen', 'glm', 'deepseek', 'yi-', 'minicpm', 'baichuan',
            'hunyuan', 'internlm', 'ernie', 'ling', 'kimi']
        .any(lower.contains);
  }
}

/// 模型广场：分页搜索 HuggingFace / 魔搭，按文件事实标注能力，给出可下载条目。
class ModelPlazaService {
  ModelPlazaService._();

  static const Duration _timeout = Duration(seconds: 20);

  /// HF 游标分页：返回模型 + 下一页游标。
  /// HF 在响应头 `Link` 里给出 `rel="next"` 的 cursor。
  static Future<(List<PlazaModel>, String?)> searchHuggingFace({
    required PlazaFilter filter,
    String? cursor,
    int limit = 20,
    int? deviceRamMb,
  }) async {
    final sort = switch (filter.sort) {
      'likes' => 'likes',
      'recent' => 'lastModified',
      _ => 'downloads',
    };
    final params = {
      'filter': 'gguf',
      'sort': sort,
      'direction': '-1',
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final query = Uri.encodeQueryComponent(filter.query.trim().isEmpty
        ? 'gguf'
        : filter.query.trim());
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    const hosts = ['https://huggingface.co', 'https://hf-mirror.com'];
    for (final host in hosts) {
      try {
        final client = HttpClient();
        client.connectionTimeout = _timeout;
        final request = await client
            .getUrl(Uri.parse('$host/api/models?search=$query&$queryString'));
        final response = await request.close().timeout(_timeout);
        if (response.statusCode != 200) {
          client.close();
          continue;
        }
        final body = await response.transform(utf8.decoder).join();
        final linkHeader = response.headers.value('link');
        client.close();
        final decoded = jsonDecode(body);
        if (decoded is! List) return (<PlazaModel>[], null);
        final models = <PlazaModel>[];
        for (final raw in decoded.whereType<Map>()) {
          final item = Map<String, dynamic>.from(raw);
          final plaza = await _enrichHf(host, item, filter, deviceRamMb);
          if (plaza != null) models.add(plaza);
        }
        return (models, _nextCursor(linkHeader));
      } catch (e) {
        debugPrint('[Plaza] $host 搜索失败: $e');
      }
    }
    return (<PlazaModel>[], null);
  }

  static String? _nextCursor(String? linkHeader) {
    if (linkHeader == null) return null;
    final match =
        RegExp(r'<[^>]*[?&]cursor=([^>&"]+)[^>]*>;\s*rel="next"')
            .firstMatch(linkHeader);
    return match?.group(1);
  }

  /// 取仓库真实文件清单 → 能力标注（有 mmproj 才是真能看图）+ 筛选。
  static Future<PlazaModel?> _enrichHf(
    String host,
    Map<String, dynamic> item,
    PlazaFilter filter,
    int? deviceRamMb,
  ) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty || !id.toLowerCase().contains('gguf')) return null;
    final name = id.split('/').last;

    // 服务端能力预筛（省请求）：明显不是视觉/思考家族的先排除。
    if (filter.visionOnly &&
        !ModelCapabilities.isVisionFamily(name) &&
        !name.toLowerCase().contains('vl')) {
      return null;
    }
    if (filter.thinkingOnly && !ModelCapabilities.supportsThinking(name)) {
      return null;
    }
    if (filter.chineseOnly && !PlazaModel._isChinese(name)) return null;

    // 列表阶段**不逐个仓库拉文件清单**（15 个模型 = 15 次请求，会像卡死）；
    // 只用名字做家族判断，真实文件在详情页按需解析。
    final heuristicVision = ModelCapabilities.isVisionFamily(name) ||
        name.toLowerCase().contains('vl');
    if (filter.visionOnly && !heuristicVision) return null;
    if (filter.maxSizeGb > 0) {
      // 体积筛选在列表阶段只能放宽处理（真实体积要进详情页才知道）。
      // 这里不拦，详情页会给出真实体积与"装得下吗"。
    }

    final downloads = (item['downloads'] as num?)?.toInt() ?? 0;
    final likes = (item['likes'] as num?)?.toInt() ?? 0;
    return PlazaModel(
      info: LocalModelInfo(
        id: 'hf_$id',
        name: name,
        description: 'HuggingFace · $downloads 次下载 · $likes 赞'
            '（点「详情」查看真实文件与体积）',
        // 占位地址：进详情页会解析成真实文件清单。
        downloadUrl: 'https://huggingface.co/$id',
        sizeBytes: 0,
        quantization: '待解析',
        ramRequired: '—',
        tags: ['HuggingFace'],
      ),
      hasProjector: heuristicVision,
      supportsThinking: ModelCapabilities.supportsThinking(name),
      downloads: downloads,
      likes: likes,
      sourceLabel: 'HuggingFace',
    );
  }

  /// 详情页按需解析：拿到真实文件清单与体积（含视觉投影）。
  static Future<PlazaModel?> resolveDetail(
    PlazaModel model, {
    int? deviceRamMb,
  }) async {
    final id = model.info.id.replaceFirst('hf_', '');
    final segments = id.split('/');
    if (segments.length < 2) return null;
    final files = await CommunityModelService.resolveHuggingFaceRepo(
        segments[0], segments.sublist(1).join('/'));
    if (files.isEmpty) return null;
    final projector = _pickProjector(files);
    final mainFiles = files
        .where((f) => !ModelCapabilities.isProjectorFile(f.fileName))
        .toList();
    if (mainFiles.isEmpty) return null;
    final recommended =
        CommunityModelService.pickVariant(mainFiles, deviceRamMb: deviceRamMb) ??
            mainFiles.first;
    final totalGb = (recommended.sizeBytes + (projector?.sizeBytes ?? 0)) /
        (1024 * 1024 * 1024);
    return PlazaModel(
      info: LocalModelInfo(
        id: model.info.id,
        name: model.info.name,
        description: 'HuggingFace · ${model.downloads} 次下载'
            '${projector != null ? ' · 含视觉投影（可看图）' : ''}'
            ' · ${mainFiles.length} 个版本可选',
        downloadUrl: recommended.downloadUrl,
        sizeBytes: recommended.sizeBytes,
        quantization: recommended.quantization,
        ramRequired: totalGb > 0
            ? '~${(totalGb * 1.35).toStringAsFixed(1)} GB'
            : '—',
        tags: ['HuggingFace'],
        variants: mainFiles,
        mmProjUrl: projector?.downloadUrl,
      ),
      hasProjector: projector != null,
      projector: projector,
      supportsThinking: model.supportsThinking,
      downloads: model.downloads,
      likes: model.likes,
      sourceLabel: model.sourceLabel,
    );
  }

  /// 从文件清单里挑视觉投影（优先 f16，体积和精度均衡）。
  static ModelFileVariant? _pickProjector(List<ModelFileVariant> files) {
    final projectors = files
        .where((f) => ModelCapabilities.isProjectorFile(f.fileName))
        .toList();
    if (projectors.isEmpty) return null;
    projectors.sort((a, b) {
      int rank(String name) {
        final lower = name.toLowerCase();
        if (lower.contains('f16')) return 0;
        if (lower.contains('bf16')) return 1;
        return 2; // f32 等
      }

      final byRank = rank(a.fileName).compareTo(rank(b.fileName));
      if (byRank != 0) return byRank;
      return a.sizeBytes.compareTo(b.sizeBytes);
    });
    return projectors.first;
  }
}
