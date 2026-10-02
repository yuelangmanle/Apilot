import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_catalog.dart';

/// 从 HuggingFace / ModelScope 社区实时获取模型列表。
///
/// 列表与**文件清单/大小**都来自真实 API：
/// - HF:     `/api/models?search=...` + `/api/models/{id}?blobs=true`
/// - 魔搭:   `/api/v1/models?Search=...` + `/api/v1/models/{repo}/repo/files`
/// 下载地址取仓库里真实存在的 GGUF 文件名（不再猜测文件名，避免 404）。
class CommunityModelService {
  CommunityModelService._();

  static const Duration _timeout = Duration(seconds: 15);

  /// 结果缓存（10 分钟），避免每次进模型商店都重新打一圈 API。
  static List<LocalModelInfo>? _hfCache;
  static List<LocalModelInfo>? _msCache;
  static DateTime? _hfCacheAt;
  static DateTime? _msCacheAt;
  static const Duration _cacheTtl = Duration(minutes: 10);

  /// 从 HuggingFace 搜索 GGUF 模型（含真实文件清单）。
  /// huggingface.co 在国内被墙 → 自动回退 hf-mirror.com。
  static Future<List<LocalModelInfo>> fetchHuggingFaceModels({
    String query = 'gguf',
    int limit = 12,
    int? deviceRamMb,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _hfCache != null &&
        _hfCacheAt != null &&
        DateTime.now().difference(_hfCacheAt!) < _cacheTtl) {
      return _hfCache!;
    }
    const hosts = ['https://huggingface.co', 'https://hf-mirror.com'];
    for (final host in hosts) {
      final models = await _fetchHfFromHost(host,
          query: query, limit: limit, deviceRamMb: deviceRamMb);
      if (models.isNotEmpty) {
        debugPrint('[CommunityModels] HF 数据源: $host（${models.length} 个）');
        _hfCache = models;
        _hfCacheAt = DateTime.now();
        return models;
      }
    }
    debugPrint('[CommunityModels] HF 两个源均不可达');
    return [];
  }

  /// 从 ModelScope（魔搭）搜索 GGUF 模型（含真实文件清单）。
  static Future<List<LocalModelInfo>> fetchModelScopeModels({
    String query = 'gguf',
    int limit = 12,
    int? deviceRamMb,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _msCache != null &&
        _msCacheAt != null &&
        DateTime.now().difference(_msCacheAt!) < _cacheTtl) {
      return _msCache!;
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      final uri = Uri.parse(
        'https://modelscope.cn/api/v1/models?Search=$query&PageSize=${limit * 2}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return [];
      final data = decoded['Data'];
      if (data is! Map) return [];
      final models = data['Models'];
      if (models is! List) return [];

      // 只保留 GGUF 仓库，逐个换取真实文件清单。
      final candidates = models
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((m) {
        final path = (m['Path'] as String? ?? '').toLowerCase();
        final name = (m['Name'] as String? ?? '').toLowerCase();
        return path.isNotEmpty && (name.contains('gguf') || path.contains('gguf'));
      })
          .take(limit)
          .toList();

      final results = await _mapBounded(candidates, 4, (item) async {
        final path = item['Path'] as String? ?? '';
        final files = await _fetchModelScopeFiles(path);
        return _buildModel(
          id: 'ms_$path',
          name: item['Name'] as String? ?? path.split('/').last,
          origin: 'ModelScope（魔搭）',
          downloads: (item['Downloads'] as num?)?.toInt() ?? 0,
          files: files,
          deviceRamMb: deviceRamMb,
          tag: 'ModelScope',
        );
      });

      final modelsOut = results.whereType<LocalModelInfo>().toList();
      if (modelsOut.isNotEmpty) {
        _msCache = modelsOut;
        _msCacheAt = DateTime.now();
      }
      return modelsOut;
    } catch (e) {
      debugPrint('[CommunityModels] ModelScope 拉取失败: $e');
      return [];
    }
  }

  static Future<List<LocalModelInfo>> _fetchHfFromHost(
    String host, {
    required String query,
    required int limit,
    int? deviceRamMb,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      final uri = Uri.parse(
        '$host/api/models?search=$query&sort=downloads&limit=$limit&filter=text-generation',
      );
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! List) return [];

      final items = decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((m) {
        final id = (m['id'] as String? ?? '').toLowerCase();
        return id.isNotEmpty && id.contains('gguf');
      }).toList();

      // 逐个取真实文件清单（真实文件名 + 真实大小）。
      final results = await _mapBounded(items, 4, (item) async {
        final id = item['id'] as String;
        final files = await _fetchHfFiles(host, id);
        return _buildModel(
          id: 'hf_$id',
          name: id.split('/').last,
          origin: 'HuggingFace',
          downloads: (item['downloads'] as num?)?.toInt() ?? 0,
          files: files,
          deviceRamMb: deviceRamMb,
          tag: 'HuggingFace',
        );
      });
      return results.whereType<LocalModelInfo>().toList();
    } catch (e) {
      debugPrint('[CommunityModels] $host 拉取失败: $e');
      return [];
    }
  }

  /// HF 仓库真实文件清单（`?blobs=true` 返回每个文件的字节数）。
  static Future<List<ModelFileVariant>> _fetchHfFiles(
      String host, String id) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      final request =
          await client.getUrl(Uri.parse('$host/api/models/$id?blobs=true'));
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return [];
      final siblings = decoded['siblings'];
      if (siblings is! List) return [];
      final variants = <ModelFileVariant>[];
      for (final entry in siblings.whereType<Map>()) {
        final name = entry['rfilename'] as String? ?? '';
        final size = (entry['size'] as num?)?.toInt() ?? 0;
        final quant = quantizationFromFileName(name);
        if (quant == null) continue;
        variants.add(ModelFileVariant(
          fileName: name,
          downloadUrl: '$host/$id/resolve/main/$name',
          sizeBytes: size,
          quantization: quant,
        ));
      }
      variants.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      return variants;
    } catch (e) {
      debugPrint('[CommunityModels] 取 HF 文件清单失败 $id: $e');
      return [];
    }
  }

  /// 魔搭仓库真实文件清单。
  static Future<List<ModelFileVariant>> _fetchModelScopeFiles(
      String repoPath) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = _timeout;
      final request = await client.getUrl(Uri.parse(
        'https://modelscope.cn/api/v1/models/$repoPath/repo/files'
        '?Revision=master&Root=',
      ));
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return [];
      final data = decoded['Data'];
      if (data is! Map) return [];
      final files = data['Files'];
      if (files is! List) return [];
      final variants = <ModelFileVariant>[];
      for (final entry in files.whereType<Map>()) {
        final filePath = entry['Path'] as String? ?? '';
        final size = (entry['Size'] as num?)?.toInt() ?? 0;
        final quant = quantizationFromFileName(filePath);
        if (quant == null) continue;
        variants.add(ModelFileVariant(
          fileName: filePath,
          downloadUrl:
              'https://modelscope.cn/models/$repoPath/resolve/master/$filePath',
          sizeBytes: size,
          quantization: quant,
        ));
      }
      variants.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
      return variants;
    } catch (e) {
      debugPrint('[CommunityModels] 取魔搭文件清单失败 $repoPath: $e');
      return [];
    }
  }

  /// 解析 HuggingFace 仓库的真实文件清单（供"粘贴链接"使用）。
  static Future<List<ModelFileVariant>> resolveHuggingFaceRepo(
    String owner,
    String repo,
  ) async {
    final id = '$owner/$repo';
    for (final host in const ['https://huggingface.co', 'https://hf-mirror.com']) {
      final files = await _fetchHfFiles(host, id);
      if (files.isNotEmpty) return files;
    }
    return [];
  }

  /// 解析魔搭仓库的真实文件清单（供"粘贴链接"使用）。
  static Future<List<ModelFileVariant>> resolveModelScopeRepo(
      String repoPath) async {
    final normalized = repoPath.replaceFirst(RegExp(r'^/'), '');
    return _fetchModelScopeFiles(normalized);
  }

  /// 从文件名识别量化等级；识别不出（fp16/分片/非 gguf）返回 null。
  static String? quantizationFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (!lower.endsWith('.gguf')) return null;
    // 分片模型需要多文件合并，App 内不支持 → 跳过。
    if (RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(lower)) return null;
    // 未量化的全精度权重体积过大（fp16/f32/bf16），不作为候选。
    if (RegExp(r'(^|[-_.])(f16|fp16|f32|bf16|fp32)([-_.]|$)')
        .hasMatch(lower)) {
      return null;
    }
    final match = RegExp(
      r'(IQ\d+_[A-Z0-9]+|Q\d+_K_[A-Z]+|Q\d+_K|Q\d+_\d+|MXFP4)',
      caseSensitive: false,
    ).firstMatch(fileName.toUpperCase());
    if (match == null) return null;
    return match.group(1)!.toUpperCase();
  }

  /// 由文件清单生成模型条目：默认下载地址 = 推荐的量化版本。
  static LocalModelInfo? _buildModel({
    required String id,
    required String name,
    required String origin,
    required int downloads,
    required List<ModelFileVariant> files,
    required int? deviceRamMb,
    required String tag,
  }) {
    if (files.isEmpty) return null; // 仓库里没有可直接下载的 GGUF
    final recommended =
        pickVariant(files, deviceRamMb: deviceRamMb) ?? files.first;
    final ramGb = recommended.sizeBytes > 0
        ? ((recommended.sizeBytes / (1024 * 1024 * 1024)) * 1.35)
            .toStringAsFixed(1)
        : '?';
    return LocalModelInfo(
      id: id,
      name: name,
      description: '$origin · $downloads 次下载 · '
          '${files.length} 个可用版本，默认下载 ${recommended.quantization}'
          '${recommended.sizeBytes > 0 ? '（${recommended.sizeLabel}）' : ''}',
      downloadUrl: recommended.downloadUrl,
      sizeBytes: recommended.sizeBytes,
      quantization: recommended.quantization,
      ramRequired: '~$ramGb GB',
      tags: [tag],
      variants: files,
    );
  }

  /// 按设备内存挑最合适的量化：优先质量高且装得下的。
  static ModelFileVariant? pickVariant(
    List<ModelFileVariant> variants, {
    int? deviceRamMb,
  }) {
    if (variants.isEmpty) return null;
    const preference = [
      'Q4_K_M', 'Q4_K_S', 'IQ4_XS', 'Q5_K_M', 'Q3_K_M',
      'Q6_K', 'Q8_0', 'Q2_K',
    ];
    Iterable<ModelFileVariant> pool = variants;
    if (deviceRamMb != null && deviceRamMb > 0) {
      // 可用预算：内存减系统开销 1.5GB，模型约占 60%。
      final budgetBytes = (deviceRamMb - 1500) * 0.6 * 1024 * 1024;
      final fits = variants
          .where((v) => v.sizeBytes > 0 && v.sizeBytes <= budgetBytes)
          .toList();
      if (fits.isNotEmpty) pool = fits;
    }
    for (final quant in preference) {
      for (final v in pool) {
        if (v.quantization == quant) return v;
      }
    }
    // 没有常见量化：取池内最小的（体积可控优先）。
    final sorted = pool.toList()
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    return sorted.isEmpty ? variants.first : sorted.first;
  }

  /// 并发上限受限的 map（避免对社区 API 打太多并发请求）。
  static Future<List<R?>> _mapBounded<T, R>(
    List<T> items,
    int concurrency,
    Future<R?> Function(T) action,
  ) async {
    final results = <R?>[];
    for (var i = 0; i < items.length; i += concurrency) {
      final batch = items.skip(i).take(concurrency);
      final batchResults = await Future.wait(batch.map(action));
      results.addAll(batchResults);
    }
    return results;
  }
}
