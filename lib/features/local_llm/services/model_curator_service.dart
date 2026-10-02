import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/ai/ai_service.dart';
import '../../../core/services/local_llm/community_model_service.dart';
import '../../../core/services/local_llm/model_capabilities.dart';
import '../../../core/services/local_llm/model_catalog.dart';
import '../../../core/services/local_llm/model_catalog_store.dart';

/// 一次 AI 精选的结果。
class ModelCuratorResult {
  final List<SavedModelEntry> entries;
  final String? error;

  const ModelCuratorResult({this.entries = const [], this.error});
  bool get ok => entries.isNotEmpty;
}

/// 模型策展：把"浏览社区 → 挑选 → 写中文描述 → 固定到商店"交给 AI，
/// 结果持久化到本机（[ModelCatalogStore]），可离线查看与下载。
class ModelCuratorService {
  ModelCuratorService._();

  /// 让 AI 从社区列表里挑选适合的模型并写一句中文介绍。
  ///
  /// [configs] 为 AI 可用的云端配置；本地模型通过 AiService 自动复用。
  static Future<ModelCuratorResult> curate(
    List<LocalModelInfo> candidates, {
    required List<ApiConfig> configs,
    int maxPicks = 6,
    int? deviceRamMb,
  }) async {
    if (candidates.isEmpty) {
      return const ModelCuratorResult(error: '社区列表为空，先刷新社区模型');
    }

    // 只把"名字/大小/量化/来源"喂给 AI —— 不带下载地址，避免模型编造 URL。
    final catalog = candidates
        .take(40)
        .map((m) => {
              'name': m.name,
              'size': m.sizeMb,
              'quant': m.quantization,
              'source': m.tags.isEmpty ? '' : m.tags.first,
            })
        .toList();

    final ramNote = deviceRamMb != null
        ? '本机内存约 ${(deviceRamMb / 1024).toStringAsFixed(1)} GB，请优先挑选装得下的。'
        : '本机内存未知，优先挑中小尺寸。';

    final answer = await AiService.ask(
      systemPrompt: '你是本地大模型选型助手。给定候选模型清单，挑选最适合普通用户'
          '在手机上离线使用的 $maxPicks 个（兼顾中文能力、体积、活跃度），'
          '并为每个写一句中文介绍（40 字内，说清楚能干什么、大概多大）。'
          '只输出 JSON 数组，每项形如 '
          '{"name":"模型名（必须与清单中的 name 完全一致）","desc":"介绍",'
          '"tags":["中文","推理"]}。不要输出任何其他文字。',
      userPrompt: '$ramNote\n候选清单（JSON）：\n${jsonEncode(catalog)}',
      configs: configs,
      maxTokens: 1200,
    );

    if (answer == null) {
      return const ModelCuratorResult(
          error: 'AI 未配置或调用失败：可先在「设置 → AI 设置」里选择云端配置或本地模型');
    }

    final picks = _parsePicks(answer);
    if (picks.isEmpty) {
      return const ModelCuratorResult(error: 'AI 返回的内容无法解析，请重试');
    }

    // 把 AI 的选择映射回真实条目（下载地址/大小一律用我们抓到的真实数据）。
    final byName = {for (final m in candidates) m.name.toLowerCase(): m};
    final entries = <SavedModelEntry>[];
    for (final pick in picks) {
      final name = (pick['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final model = byName[name.toLowerCase()] ??
          _fuzzyMatch(byName, name);
      if (model == null) continue;
      final desc = (pick['desc'] as String? ?? '').trim();
      final tags = (pick['tags'] as List?)
              ?.whereType<String>()
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          const <String>[];
      entries.add(SavedModelEntry(
        info: LocalModelInfo(
          id: model.id,
          name: model.name,
          description: desc.isEmpty ? model.description : desc,
          downloadUrl: model.downloadUrl,
          sizeBytes: model.sizeBytes,
          quantization: model.quantization,
          ramRequired: model.ramRequired,
          tags: [
            ...tags,
            ...ModelCapabilities.isVisionFamily(model.name)
                ? ['多模态']
                : const <String>[],
            if (ModelCapabilities.supportsThinking(model.name)) '可深度思考',
          ],
          variants: model.variants,
        ),
        source: 'ai',
        addedAt: DateTime.now(),
      ));
    }
    if (entries.isEmpty) {
      return const ModelCuratorResult(error: 'AI 挑选的模型与清单对不上，请重试');
    }
    return ModelCuratorResult(entries: entries);
  }

  /// 容错解析 AI 返回的 JSON 数组（允许 ```json 围栏与前后说明文字）。
  static List<Map<String, dynamic>> _parsePicks(String answer) {
    var text = answer.replaceAll(RegExp(r'```(?:json)?'), '').trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('[Curator] 解析 AI 结果失败: $e');
      return const [];
    }
  }

  static LocalModelInfo? _fuzzyMatch(
      Map<String, LocalModelInfo> byName, String name) {
    final target = name.toLowerCase();
    for (final entry in byName.entries) {
      if (entry.key.contains(target) || target.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 粘贴"模型库/合集页"时：把里面的仓库逐个解析成可下载条目。
  ///
  /// 支持一次粘贴多个链接（换行/空格分隔），或一个 HF/魔搭 搜索页链接
  /// （从页面里提取 owner/repo 形态的链接）。
  static Future<List<LocalModelInfo>> resolvePastedLinks(
    String input, {
    int? deviceRamMb,
    void Function(int done, int total)? onProgress,
  }) async {
    final repos = extractRepositories(input);
    if (repos.isEmpty) return const [];
    final results = <LocalModelInfo>[];
    var done = 0;
    for (final repo in repos) {
      List<ModelFileVariant> files = const [];
      if (repo.host == 'modelscope') {
        files =
            await CommunityModelService.resolveModelScopeRepo(repo.path);
      } else {
        final segments = repo.path.split('/');
        if (segments.length >= 2) {
          files = await CommunityModelService.resolveHuggingFaceRepo(
              segments[0], segments.sublist(1).join('/'));
        }
      }
      done++;
      onProgress?.call(done, repos.length);
      if (files.isEmpty) continue;
      final recommended = CommunityModelService.pickVariant(files,
              deviceRamMb: deviceRamMb) ??
          files.first;
      final name = repo.path.split('/').last;
      results.add(LocalModelInfo(
        id: '${repo.host}_${repo.path}',
        name: name,
        description: '从粘贴链接解析 · ${files.length} 个可下载版本'
            ' · 默认 ${recommended.quantization}',
        downloadUrl: recommended.downloadUrl,
        sizeBytes: recommended.sizeBytes,
        quantization: recommended.quantization,
        ramRequired: recommended.sizeBytes > 0
            ? '~${((recommended.sizeBytes / (1024 * 1024 * 1024)) * 1.35).toStringAsFixed(1)} GB'
            : '—',
        tags: [repo.host == 'modelscope' ? 'ModelScope' : 'HuggingFace'],
        variants: files,
      ));
    }
    return results;
  }

  /// 从任意文本里提取仓库坐标（owner/repo 或魔搭 models/owner/repo）。
  static List<RepoRef> extractRepositories(String input) {
    final refs = <RepoRef>[];
    void add(RepoRef ref) {
      if (!refs.any((r) => r.host == ref.host && r.path == ref.path)) {
        refs.add(ref);
      }
    }

    final urlPattern =
        RegExp('https?://[^\\s"\'<>()\\[\\]]+', caseSensitive: false);
    for (final match in urlPattern.allMatches(input)) {
      final raw = match.group(0)!;
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final host = uri.host.toLowerCase();
      if (host.contains('huggingface.co') || host.contains('hf-mirror.com')) {
        if (segments.length < 2) continue;
        // 跳过 tree/resolve/blob 等子路径，只取 owner/repo。
        final owner = segments[0];
        final repo = segments[1];
        if (['models', 'datasets', 'spaces', 'tree', 'resolve', 'blob']
            .contains(owner.toLowerCase())) {
          continue;
        }
        add(RepoRef('huggingface', '$owner/$repo'));
      } else if (host.contains('modelscope.cn')) {
        final idx = segments.indexOf('models');
        if (idx < 0 || idx + 2 >= segments.length) continue;
        add(RepoRef('modelscope', '${segments[idx + 1]}/${segments[idx + 2]}'));
      }
    }

    // 裸 owner/repo（老手直接粘贴坐标）：一行一个。
    for (final line in input.split(RegExp(r'[\s,;]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.contains('://')) continue;
      if (RegExp(r'^[\w.\-]+/[\w.\-]+$').hasMatch(trimmed)) {
        add(RepoRef('huggingface', trimmed));
      }
    }
    return refs;
  }
}

/// 粘贴解析出的仓库坐标。
class RepoRef {
  final String host; // huggingface / modelscope
  final String path; // owner/repo
  const RepoRef(this.host, this.path);
}
