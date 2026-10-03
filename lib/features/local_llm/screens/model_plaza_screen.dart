import 'dart:async';

import 'package:flutter/material.dart';
import '../../api_management/providers/api_provider.dart';
import '../../../core/services/ai/ai_service.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../../../core/services/local_llm/device_capabilities.dart';
import '../../../core/services/local_llm/model_catalog.dart';
import '../../../core/services/local_llm/model_plaza_service.dart';
import '../../../shared/theme/color_scheme.dart';

/// 模型广场：像真正的社区一样翻模型。
///
/// - 分页无限滚动（HuggingFace 游标分页）
/// - 关键词搜索 + 快捷筛选（看图 / 深度思考 / 中文 / 体积上限）
/// - 能力标签来自**文件事实**（仓库有 mmproj 才是真能看图）
/// - 详情页把"主模型 + 视觉投影"作为一组下载
class ModelPlazaScreen extends StatefulWidget {
  /// 供外部传入的下载回调（复用商店页的下载服务，保证进度统一）。
  /// [pairWithMain] 非空时表示本次下载的是视觉投影，下载完成会把它
  /// 配对到指定主模型（主模型文件名），之后打开该模型自动挂上看图。
  final void Function({
    required String url,
    required String fileName,
    required String displayName,
    String? pairWithMain,
  })? onDownloadRequested;

  const ModelPlazaScreen({super.key, this.onDownloadRequested});

  @override
  State<ModelPlazaScreen> createState() => _ModelPlazaScreenState();
}

class _ModelPlazaScreenState extends State<ModelPlazaScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<PlazaModel> _models = [];
  PlazaFilter _filter = const PlazaFilter();
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int? _deviceRamMb;
  String? _resolvingDetail;
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _researching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initDevice();
    _search(reset: true);
  }

  Future<void> _initDevice() async {
    try {
      final device = await DeviceCapabilities.detect();
      if (mounted) setState(() => _deviceRamMb = device.ramMb);
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final remaining = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (remaining < 600 && !_loading && _hasMore) _search();
  }

  Future<void> _search({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() {
        _models.clear();
        _cursor = null;
        _hasMore = true;
        _error = null;
      });
    }
    if (!_hasMore) return;
    setState(() => _loading = true);

    try {
      final (results, nextCursor) = await ModelPlazaService.searchHuggingFace(
        filter: _filter,
        cursor: _cursor,
        limit: 15,
        deviceRamMb: _deviceRamMb,
      );
      if (!mounted) return;
      setState(() {
        _models.addAll(results.where(
            (m) => !_models.any((existing) => existing.info.id == m.info.id)));
        _cursor = nextCursor;
        _hasMore = nextCursor != null && results.isNotEmpty;
        _loading = false;
        if (results.isEmpty && _models.isEmpty) {
          _error = '没有匹配的模型：试试放宽筛选（去掉"看图/思考"或提高体积上限）';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '搜索失败：$e';
        });
      }
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _filter = _filter.copyWith(query: value);
      _search(reset: true);
    });
  }

  void _applyFilter(PlazaFilter next) {
    setState(() => _filter = next);
    _search(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('已选 ${_selected.length} 个')
            : const Text('模型广场'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: _researching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.psychology_outlined),
              tooltip: '交给 AI 调研（这些是什么/区别/推荐哪个版本）',
              onPressed: (_selected.isEmpty || _researching)
                  ? null
                  : _researchSelected,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '退出选择',
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '多选（可交给 AI 调研）',
              onPressed: () => setState(() => _selectMode = true),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: '搜索模型名或作者（如 qwen、gemma、vl）',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('看图', _filter.visionOnly,
                          (v) => _applyFilter(_filter.copyWith(visionOnly: v))),
                      _chip('深度思考', _filter.thinkingOnly,
                          (v) =>
                              _applyFilter(_filter.copyWith(thinkingOnly: v))),
                      _chip('中文', _filter.chineseOnly,
                          (v) => _applyFilter(_filter.copyWith(chineseOnly: v))),
                      _chip(
                          _filter.maxSizeGb > 0
                              ? '≤${_filter.maxSizeGb.toStringAsFixed(0)}GB'
                              : '体积不限',
                          _filter.maxSizeGb > 0,
                          (v) => _applyFilter(_filter.copyWith(
                              maxSizeGb: v ? 6 : 0))),
                      _chip(
                          _filter.sort == 'likes' ? '按点赞' : '按下载',
                          false,
                          (_) => _applyFilter(_filter.copyWith(
                              sort: _filter.sort == 'likes'
                                  ? 'downloads'
                                  : 'likes'))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _search(reset: true),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _models.length + (_loading || _error != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _models.length) {
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: secondary)),
                );
              }
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _buildCard(_models[index], secondary);
          },
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, ValueChanged<bool> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildCard(PlazaModel model, Color secondary) {
    final resolving = _resolvingDetail == model.info.id;
    final canFit = model.info.sizeBytes <= 0 || _deviceRamMb == null
        ? null
        : model.bundleSizeGb * 1.35 * 1024 <= _deviceRamMb!;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_selectMode) ...[
                  Icon(
                    _selected.contains(model.info.id)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: _selected.contains(model.info.id)
                        ? AppColors.primary
                        : secondary,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: _selectMode
                        ? () => setState(() {
                              if (!_selected.remove(model.info.id)) {
                                _selected.add(model.info.id);
                              }
                            })
                        : null,
                    child: Text(model.info.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                if (canFit != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (canFit ? AppColors.primary : AppColors.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(canFit ? '装得下' : '可能装不下',
                        style: TextStyle(
                            fontSize: 10,
                            color: canFit
                                ? AppColors.primary
                                : AppColors.error)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in model.capabilityTags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tag,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.secondaryText)),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(model.info.quantization,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.primary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              model.info.sizeBytes > 0
                  ? '主模型 ${model.info.sizeMb}'
                      '${model.projector != null ? ' + 视觉投影 ${model.projector!.sizeLabel}' : ''}'
                      ' · ${model.info.ramRequired}'
                      ' · ${model.downloads} 次下载'
                  : '${model.downloads} 次下载 · 点「详情」解析真实体积',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: resolving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download, size: 18),
                    // 列表阶段还不知道真实量化版本：先解析再下载，避免下错文件。
                    label: Text(resolving
                        ? '解析中…'
                        : (model.info.sizeBytes > 0 ? '下载模型' : '解析并下载')),
                    onPressed: resolving ? null : () => _download(model),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showDetail(model, secondary),
                  child: const Text('详情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 下载：有投影的连投影一起下（这是"能看图"的完整包）。
  Future<void> _download(PlazaModel model) async {
    final handler = widget.onDownloadRequested;
    if (handler == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('当前入口未接入下载（请从模型商店进入）')));
      return;
    }
    // 列表阶段拿到的条目还没解析真实文件：先解析（含视觉投影一起下）。
    if (model.info.sizeBytes <= 0) {
      final primary = widget.onDownloadRequested;
      if (primary == null) return;
      await _showDetail(model, Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkTextSecondary
          : AppColors.textSecondary);
      return;
    }
    handler(
      url: model.info.downloadUrl,
      fileName: model.info.downloadUrl.split('/').last,
      displayName: model.info.name,
    );
    if (model.projector != null) {
      handler(
        url: model.projector!.downloadUrl,
        fileName: model.projector!.fileName,
        displayName: '${model.info.name} 视觉投影',
        pairWithMain: model.info.downloadUrl.split('/').last,
      );
    }
  }

  /// 完整包下载：多个版本时先让用户选具体量化版本，再连同投影一起下
  /// 并自动配对。单版本直接下——按钮上已写明版本，不再有"不知道下的是哪个"。
  Future<void> _downloadCompletePack(PlazaModel model) async {
    final handler = widget.onDownloadRequested;
    if (handler == null) return;
    // 未解析（列表项）：走详情解析流程。
    if (model.info.sizeBytes <= 0) {
      await _showDetail(model, Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkTextSecondary
          : AppColors.textSecondary);
      return;
    }
    ModelFileVariant? chosen;
    if (model.info.variants.length > 1) {
      chosen = await _pickVariant(model);
      if (chosen == null) return;
    } else {
      chosen = model.info.variants.isEmpty ? null : model.info.variants.first;
    }
    final variant = chosen;
    final mainName = variant?.fileName ??
        model.info.downloadUrl.split('/').last;
    handler(
      url: variant?.downloadUrl ?? model.info.downloadUrl,
      fileName: mainName,
      displayName: '${model.info.name} '
          '${variant?.quantization ?? model.info.quantization}',
    );
    if (model.projector != null) {
      handler(
        url: model.projector!.downloadUrl,
        fileName: model.projector!.fileName,
        displayName: '${model.info.name} 视觉投影',
        pairWithMain: mainName,
      );
    }
  }

  /// 版本选择对话框（量化版本清单，带体积；推荐项排前由服务层排好序）。
  Future<ModelFileVariant?> _pickVariant(PlazaModel model) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = dark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return showModalBottomSheet<ModelFileVariant>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('选择「${model.info.name}」的版本',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('选中的版本将与配套视觉投影一起下载并自动配对。',
                style: TextStyle(fontSize: 11, color: secondary)),
            for (final variant in model.info.variants.take(20))
              ListTile(
                dense: true,
                title: Text(variant.quantization,
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text('${variant.fileName} · ${variant.sizeLabel}',
                    style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.download, size: 18),
                onTap: () => Navigator.pop(sheetContext, variant),
              ),
          ],
        ),
      ),
    );
  }

  /// 把选中的模型交给 AI 调研：这是干什么的 / 各版本区别 / 推荐哪个。
  Future<void> _researchSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = _models
        .where((m) => _selected.contains(m.info.id))
        .take(6)
        .toList();
    if (picked.isEmpty) return;
    setState(() => _researching = true);
    try {
      final configs = context.read<ApiProvider>().allApiConfigs;
      final lines = picked
          .map((m) => '- ${m.info.name}｜${m.info.sizeMb}｜'
              '${m.info.quantization}｜下载 ${m.downloads} 次'
              '${m.hasProjector ? '｜疑似多模态' : ''}'
              '${m.supportsThinking ? '｜支持深度思考' : ''}')
          .join('\n');
      final ramNote = _deviceRamMb != null
          ? '用户设备内存约 ${(_deviceRamMb! / 1024).toStringAsFixed(1)} GB。'
          : '设备内存未知。';
      final answer = await AiService.ask(
        systemPrompt: '你是模型选型顾问。用户会给你一批候选模型，请输出：\n'
            '1) 每个模型一句话说明它能干什么、适合什么场景；\n'
            '2) 它们之间的关键区别（能力/体积/语言/量化）；\n'
            '3) 明确推荐一个（结合用户设备内存），并说明理由；\n'
            '4) 如果要下载，推荐选哪个量化版本。\n'
            '用简洁中文，不要 Markdown 标题，控制在 400 字内。',
        userPrompt: '$ramNote\n候选：\n$lines',
        configs: configs,
        maxTokens: 900,
      );
      if (!mounted) return;
      setState(() => _researching = false);
      if (answer == null || answer.trim().isEmpty) {
        messenger.showSnackBar(const SnackBar(
            content: Text('AI 未配置或调用失败：可先在「设置 → AI 设置」配置来源')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('AI 调研（${picked.length} 个模型）'),
          content: SingleChildScrollView(
              child: SelectableText(answer,
                  style: const TextStyle(fontSize: 13, height: 1.6))),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: answer));
                Navigator.pop(dialogContext);
              },
              child: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _researching = false);
      messenger.showSnackBar(SnackBar(
          content: Text('调研失败：$e'), backgroundColor: AppColors.error));
    }
  }

  /// 详情：按需解析真实文件清单（列表阶段不做，避免卡死）。
  Future<void> _showDetail(PlazaModel model, Color secondary) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _resolvingDetail = model.info.id);
    PlazaModel? resolved;
    try {
      resolved = await ModelPlazaService.resolveDetail(
          model, deviceRamMb: _deviceRamMb);
    } catch (e) {
      debugPrint('[Plaza] 详情解析失败: $e');
    }
    if (!mounted) return;
    setState(() => _resolvingDetail = null);
    if (resolved == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('没能解析这个仓库的文件清单：可能网络受限（试试挂 VPN）'
            '或该仓库不含 GGUF。'),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 4),
      ));
      return;
    }
    final detail = resolved;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(detail.info.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(detail.info.description,
                  style: TextStyle(fontSize: 12, color: secondary)),
              const SizedBox(height: 12),
              if (detail.capabilityTags.isNotEmpty) ...[
                const Text('能力',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(detail.capabilityTags.join(' · '),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
              ],
              const Text('文件（真实体积）',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              if (detail.projector != null)
                const Text('「型号 + 投影」= 下载后自动配对，打开即可看图；'
                    '“只下模型”则不含看图能力。',
                    style: TextStyle(fontSize: 11, color: AppColors.primary)),
              for (final variant in detail.info.variants.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(variant.quantization,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '${variant.fileName} · ${variant.sizeLabel}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (detail.projector != null)
                      IconButton(
                        icon: const Icon(Icons.link, size: 18),
                        tooltip: '下这个版本 + 配套投影（自动配对）',
                        onPressed: () {
                          final handler = widget.onDownloadRequested;
                          handler?.call(
                            url: variant.downloadUrl,
                            fileName: variant.fileName,
                            displayName: '${detail.info.name} '
                                '${variant.quantization}（含投影）',
                          );
                          handler?.call(
                            url: detail.projector!.downloadUrl,
                            fileName: detail.projector!.fileName,
                            displayName:
                                '${detail.info.name} 视觉投影',
                            pairWithMain: variant.fileName,
                          );
                          Navigator.pop(sheetContext);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.download, size: 18),
                      tooltip: '只下这个版本',
                      onPressed: () {
                        widget.onDownloadRequested?.call(
                          url: variant.downloadUrl,
                          fileName: variant.fileName,
                          displayName: variant.quantization,
                        );
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ]),
                ),
              if (detail.projector != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('视觉投影（看图必需）',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${detail.projector!.fileName} · ${detail.projector!.sizeLabel}\n'
                        'mmproj 是模型专用的（不能跨模型混用），这份与当前模型配套。',
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 完整包按钮：明确写出将要下载的具体版本与投影文件名，
              // 不再让用户猜"一键下载下的是哪个"；有多个版本时先弹选择。
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(detail.projector != null
                    ? '下载完整包：${detail.info.quantization}'
                        '（${detail.info.sizeMb}）+ 投影'
                    : '下载 ${detail.info.quantization}（${detail.info.sizeMb}）'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _downloadCompletePack(detail);
                },
              ),
              if (detail.projector != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    widget.onDownloadRequested?.call(
                      url: detail.info.downloadUrl,
                      fileName: detail.info.downloadUrl.split('/').last,
                      displayName: detail.info.name,
                    );
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('只要文本模型（不要看图）'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
