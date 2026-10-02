import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/local_llm/device_capabilities.dart';
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
  final void Function({
    required String url,
    required String fileName,
    required String displayName,
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
        title: const Text('模型广场'),
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
    final canFit = _deviceRamMb == null
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
                Expanded(
                  child: Text(model.info.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
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
              '主模型 ${model.info.sizeMb}'
              '${model.projector != null ? ' + 视觉投影 ${model.projector!.sizeLabel}' : ''}'
              ' · ${model.info.ramRequired}'
              ' · ${model.downloads} 次下载',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(model.projector != null
                        ? '下载（含看图）'
                        : '下载模型'),
                    onPressed: () => _download(model),
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
      );
    }
  }

  void _showDetail(PlazaModel model, Color secondary) {
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
              Text(model.info.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(model.info.description,
                  style: TextStyle(fontSize: 12, color: secondary)),
              const SizedBox(height: 12),
              if (model.capabilityTags.isNotEmpty) ...[
                const Text('能力',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(model.capabilityTags.join(' · '),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
              ],
              const Text('文件（真实体积）',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              for (final variant in model.info.variants.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(variant.quantization,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '${variant.fileName} · ${variant.sizeLabel}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
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
                ),
              if (model.projector != null) ...[
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
                        '${model.projector!.fileName} · ${model.projector!.sizeLabel}\n'
                        'mmproj 是模型专用的（不能跨模型混用），这份与当前模型配套。',
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(model.projector != null
                    ? '下载完整包（模型 + 视觉投影）'
                    : '下载模型'),
                onPressed: () {
                  _download(model);
                  Navigator.pop(sheetContext);
                },
              ),
              if (model.projector != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    widget.onDownloadRequested?.call(
                      url: model.info.downloadUrl,
                      fileName: model.info.downloadUrl.split('/').last,
                      displayName: model.info.name,
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
