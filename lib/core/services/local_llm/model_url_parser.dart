
/// 解析用户粘贴的模型页面/下载链接，提取可下载的 GGUF 文件列表。
/// 支持 HuggingFace、ModelScope 页面 URL 和直接的 .gguf 下载链接。
class ModelUrlParser {
  ModelUrlParser._();

  /// 解析结果：一组候选下载 URL（按推荐度排序）+ 识别出的模型名。
  static ModelUrlParseResult parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return ModelUrlParseResult.empty();

    // 1. 直接 .gguf 链接
    if (trimmed.toLowerCase().endsWith('.gguf') &&
        (trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && (uri.host == 'huggingface.co' ||
          uri.host.contains('hf.co') ||
          uri.host.contains('modelscope.cn') ||
          uri.host.contains('hf-mirror.com'))) {
        final fileName = uri.pathSegments.last;
        return ModelUrlParseResult(
          downloadUrls: [trimmed],
          modelName: _modelNameFromFileName(fileName),
          source: trimmed,
        );
      }
    }

    // 2. HuggingFace 仓库页面
    //    https://huggingface.co/<owner>/<repo>
    //    https://huggingface.co/<owner>/<repo>/tree/main
    //    https://hf-mirror.com/<owner>/<repo>
    final hfMatch =
        RegExp(r'huggingface\.co|hf-mirror\.com').hasMatch(trimmed);
    if (hfMatch) {
      return _parseHuggingFacePage(trimmed);
    }

    // 3. ModelScope 页面
    //    https://modelscope.cn/models/<owner>/<repo>
    if (trimmed.contains('modelscope.cn/models/')) {
      return _parseModelScopePage(trimmed);
    }

    // 4. 普通文本中提取 .gguf URL
    final ggufUrls = RegExp(
      r'https?://[^\s"\x27<>]+\.gguf',
      caseSensitive: false,
    ).allMatches(trimmed).map((m) => m.group(0)!).toList();
    if (ggufUrls.isNotEmpty) {
      return ModelUrlParseResult(
        downloadUrls: ggufUrls,
        modelName: _modelNameFromFileName(
            ggufUrls.first.split('/').last),
        source: 'text-extracted',
      );
    }

    return ModelUrlParseResult.empty();
  }

  static ModelUrlParseResult _parseHuggingFacePage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return ModelUrlParseResult.empty();

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // 最少需要 owner/repo 两段
    if (segments.length < 2) return ModelUrlParseResult.empty();

    final owner = segments[0];
    final repo = segments[1];
    // 过滤非仓库段（tree/resolve/blob 等）
    if (['tree', 'resolve', 'blob', 'discussions'].contains(owner)) {
      return ModelUrlParseResult.empty();
    }

    final host = uri.host;
    final baseUrl = host == 'hf-mirror.com'
        ? 'https://hf-mirror.com/$owner/$repo'
        : 'https://huggingface.co/$owner/$repo';

    final repoName = repo.replaceAll(RegExp(r'-GGUF$|-gguf$|-GGUF$', caseSensitive: false), '');

    // 已知量化列表（按推荐度排序）
    const quants = [
      'Q4_K_M', 'Q4_K_S', 'Q5_K_M', 'Q6_K', 'Q8_0',
      'IQ4_XS', 'Q3_K_M', 'Q2_K',
    ];

    final downloadUrls = <String>[];
    final variants = <String>[];
    for (final quant in quants) {
      // 通用 GGUF 文件名模式
      final baseName = repoName.split('/').last;
      final fileName = '$baseName-$quant.gguf';
      downloadUrls.add('$baseUrl/resolve/main/$fileName');
      variants.add(quant);
    }

    return ModelUrlParseResult(
      downloadUrls: downloadUrls,
      modelName: repoName,
      source: baseUrl,
      repoOwner: owner,
      repoName: repo,
      variants: variants,
    );
  }

  static ModelUrlParseResult _parseModelScopePage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return ModelUrlParseResult.empty();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) return ModelUrlParseResult.empty();
    // modelscope.cn/models/{namespace}/{name}
    final nsIdx = segments.indexOf('models');
    if (nsIdx < 0 || nsIdx + 2 >= segments.length) {
      return ModelUrlParseResult.empty();
    }
    final owner = segments[nsIdx + 1];
    final repo = segments[nsIdx + 2];
    return ModelUrlParseResult(
      downloadUrls: [],
      modelName: repo,
      source: url,
      repoOwner: owner,
      repoName: repo,
      note: 'ModelScope 需手动浏览模型文件获取 .gguf 下载链接',
    );
  }

  static String _modelNameFromFileName(String fileName) {
    var name = fileName.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
    // 去掉量化后缀
    name = name.replaceAll(
        RegExp(r'[-.]?(Q[2-8]_K_S|M|IQ[0-9]_[XS]|Q[2-8]_0|Q[2-8]_K)$'), '');
    return name.replaceAll('_', ' ').trim();
  }
}

class ModelUrlParseResult {
  final List<String> downloadUrls;
  final String modelName;
  final String source;
  final String? repoOwner;
  final String? repoName;
  final List<String> variants;
  final String? note;

  const ModelUrlParseResult({
    required this.downloadUrls,
    required this.modelName,
    required this.source,
    this.repoOwner,
    this.repoName,
    this.variants = const [],
    this.note,
  });

  static ModelUrlParseResult empty() =>
      const ModelUrlParseResult(downloadUrls: [], modelName: '', source: '');

  bool get isEmpty => downloadUrls.isEmpty && note == null;
}

/// 根据设备可用内存（MB）推荐最合适的量化版本。
class QuantizationRecommender {
  QuantizationRecommender._();

  /// 从变体列表中推荐最适合给定 RAM（MB）的量化版本。
  /// 返回 null 表示没有推荐。
  static String? recommend(List<String> variants, {required int ramMb}) {
    if (variants.isEmpty) return null;
    // 可用内存减去系统开销约 1.5GB，模型文件约需占 RAM 的 60%。
    final budgetMb = (ramMb - 1500) * 0.6;

    // 按"质量最高且能装下"排序。
    const qualityOrder = [
      'Q8_0', 'Q6_K', 'Q5_K_M', 'Q4_K_M', 'Q4_K_S', 'IQ4_XS', 'Q3_K_M', 'Q2_K',
    ];

    String? best;
    int bestIndex = qualityOrder.length;
    for (final variant in variants) {
      final idx = qualityOrder.indexOf(variant);
      if (idx < 0) continue;
      // 粗略估算 Q4_K_M 约 2.5GB，其他量化按比例。
      final estimatedSizeMb = _estimateModelSize(variant);
      if (estimatedSizeMb > budgetMb) continue;
      if (idx < bestIndex) {
        best = variant;
        bestIndex = idx;
      }
    }
    return best;
  }

  static int _estimateModelSize(String quant) {
    // 以 4B 参数模型为基准。
    const sizes = {
      'Q8_0': 4300,
      'Q6_K': 3300,
      'Q5_K_M': 2900,
      'Q4_K_M': 2500,
      'Q4_K_S': 2300,
      'IQ4_XS': 2200,
      'Q3_K_M': 1900,
      'Q2_K': 1600,
    };
    return sizes[quant] ?? 2500;
  }
}
