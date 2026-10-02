import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_catalog.dart';
import '../../../core/services/local_llm/community_model_service.dart';
import '../../../core/services/local_llm/model_url_parser.dart';
import '../../../core/services/local_llm/device_capabilities.dart';
import '../../../core/services/ai/ai_service.dart';
import '../../api_management/providers/api_provider.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../shared/theme/color_scheme.dart';
import 'local_chat_screen.dart';

/// 模型商店：浏览内置模型 + 从 URL 导入 + 管理已下载模型。
class ModelStoreScreen extends StatefulWidget {
  const ModelStoreScreen({super.key});

  @override
  State<ModelStoreScreen> createState() => _ModelStoreScreenState();
}

class _ModelStoreScreenState extends State<ModelStoreScreen> {
  final ModelDownloadService _downloader = ModelDownloadService();
  final Map<String, DownloadProgress> _downloads = {};
  List<DownloadedModel> _downloaded = [];
  List<PartialDownload> _partials = [];
  List<LocalModelInfo> _communityModels = [];
  bool _loadingCommunity = false;
  bool _loading = true;
  bool _resolvingRepo = false;
  int? _deviceRamMb;
  StreamSubscription<DownloadProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    // 关键：把流事件写回 _downloads，否则进度条读的是永不更新的初始快照。
    _progressSubscription = _downloader.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.status == DownloadStatus.completed ||
            progress.status == DownloadStatus.cancelled ||
            progress.status == DownloadStatus.failed) {
          _downloads.remove(progress.taskId);
        } else {
          _downloads[progress.taskId] = progress;
        }
      });
    });
    _refreshDownloaded();
    _loadDeviceAndCommunity();
  }

  /// 先取设备内存（推荐量化要看它），再拉社区列表。
  Future<void> _loadDeviceAndCommunity() async {
    try {
      final device = await DeviceCapabilities.detect();
      _deviceRamMb = device.ramMb;
    } catch (_) {}
    await _fetchCommunity();
  }

  Future<void> _fetchCommunity({bool forceRefresh = false}) async {
    if (mounted) setState(() => _loadingCommunity = true);
    try {
      // 并行拉取 HuggingFace 与 ModelScope，任一失败不影响另一个。
      final results = await Future.wait([
        CommunityModelService.fetchHuggingFaceModels(
            deviceRamMb: _deviceRamMb, forceRefresh: forceRefresh),
        CommunityModelService.fetchModelScopeModels(
            deviceRamMb: _deviceRamMb, forceRefresh: forceRefresh),
      ]);
      if (mounted) {
        setState(() {
          _communityModels = [...results[0], ...results[1]];
          _loadingCommunity = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCommunity = false);
      }
    }
  }

  Future<void> _refreshDownloaded() async {
    final files = await ModelDownloadService.listDownloadedModels();
    final partials = await ModelDownloadService.listPartialDownloads();
    if (!mounted) return;
    setState(() {
      _downloaded = files
          .map((f) => DownloadedModel.fromFile(f))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _partials = partials;
      _loading = false;
    });
  }

  /// 下载指定文件（社区模型的多版本/内置模型共用入口）。
  Future<void> _downloadUrl({
    required String taskId,
    required String url,
    required String fileName,
    required String displayName,
  }) async {
    if (_downloads[taskId]?.isActive == true) return;
    setState(() {
      _downloads[taskId] = DownloadProgress(
        taskId: taskId,
        url: url,
        filePath: '',
        status: DownloadStatus.downloading,
      );
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _downloader.download(url, taskId, expectedFileName: fileName);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('「$displayName」下载完成'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshDownloaded();
    } on DownloadCancelledException {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('下载已暂停，可在「未完成的下载」里继续'),
              duration: Duration(seconds: 2)),
        );
      }
      await _refreshDownloaded();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _downloads.remove(taskId));
  }

  Future<void> _startDownload(LocalModelInfo model) async {
    await _downloadUrl(
      taskId: model.id,
      url: model.downloadUrl,
      fileName: model.downloadUrl.split('/').last,
      displayName: model.name,
    );
  }

  /// 选择版本：社区模型仓库里的全部真实文件（带真实大小 + 设备推荐）。
  Future<void> _chooseVariant(LocalModelInfo model) async {
    final selected = await _pickVariantDialog(
      title: '${model.name} 的版本',
      modelName: model.name,
      variants: model.variants,
      deviceSummary: _deviceRamMb != null
          ? '设备内存约 ${(_deviceRamMb! / 1024).toStringAsFixed(1)} GB'
          : null,
    );
    if (selected == null) return;
    await _downloadUrl(
      taskId: model.id,
      url: selected.downloadUrl,
      fileName: selected.fileName,
      displayName: '${model.name} ${selected.quantization}',
    );
  }

  /// 版本选择对话框：真实文件列表 + 设备推荐 + 可选 AI 分析。
  Future<ModelFileVariant?> _pickVariantDialog({
    required String title,
    required String modelName,
    required List<ModelFileVariant> variants,
    String? deviceSummary,
  }) async {
    if (variants.isEmpty) return null;
    final recommended =
        CommunityModelService.pickVariant(variants, deviceRamMb: _deviceRamMb);
    var aiAdvice = '';
    var aiLoading = false;
    return showDialog<ModelFileVariant>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final secondary =
              Theme.of(dialogContext).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary;
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '共 ${variants.length} 个版本'
                    '${deviceSummary != null ? ' · $deviceSummary' : ''}',
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                  const SizedBox(height: 8),
                  if (aiAdvice.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('AI 建议：$aiAdvice',
                          style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final variant in variants)
                            ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Text(variant.quantization,
                                      style: const TextStyle(fontSize: 13)),
                                  if (recommended?.fileName ==
                                      variant.fileName) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.success
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: const Text('推荐',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.success)),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                  '${variant.fileName} · ${variant.sizeLabel}',
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () =>
                                  Navigator.pop(dialogContext, variant),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (aiLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 分析'),
                  onPressed: () async {
                    setDialogState(() => aiLoading = true);
                    final configs =
                        context.read<ApiProvider>().allApiConfigs;
                    final device = deviceSummary ??
                        (_deviceRamMb != null
                            ? '设备内存约 ${(_deviceRamMb! / 1024).toStringAsFixed(1)} GB'
                            : '设备信息未知');
                    final advice = await AiService.ask(
                      systemPrompt:
                          '你是本地大模型部署助手。根据设备配置推荐最合适的量化版本，'
                          '只输出一句话建议（含版本名与理由），不要 Markdown。',
                      userPrompt: '$device\n'
                          '模型：$modelName\n'
                          '候选量化版本（名称/大小）：'
                          '${variants.map((v) => '${v.quantization}(${v.sizeLabel})').join('、')}\n'
                          '请推荐一个最适合现在安装的版本。',
                      configs: configs,
                      maxTokens: 150,
                    );
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        aiLoading = false;
                        aiAdvice =
                            advice ?? 'AI 未配置，已按设备内存给出本地推荐';
                      });
                    }
                  },
                ),
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
            ],
          );
        },
      ),
    );
  }

  /// 继续一个未完成的下载（HTTP Range 续传）。
  Future<void> _resumePartial(PartialDownload partial) async {
    if (!partial.resumable) return;
    await _downloadUrl(
      taskId: partial.fileName,
      url: partial.url,
      fileName: partial.fileName,
      displayName: partial.fileName,
    );
  }

  Future<void> _deletePartial(PartialDownload partial) async {
    try {
      final file = File(partial.partialPath);
      if (file.existsSync()) await file.delete();
      final sidecar = File('${partial.partialPath}.meta.json');
      // sidecar 命名为 <正式文件>.meta.json，.part 的对应文件是去掉 .part。
      final base = partial.partialPath.endsWith('.part')
          ? partial.partialPath.substring(0, partial.partialPath.length - 5)
          : partial.partialPath;
      final sidecarFile = File('$base.meta.json');
      if (sidecarFile.existsSync()) await sidecarFile.delete();
      if (sidecar.existsSync()) await sidecar.delete();
    } catch (_) {}
    await _refreshDownloaded();
  }

  void _openChat(DownloadedModel model) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalChatScreen(
          modelPath: model.filePath,
          modelName: model.name,
        ),
      ),
    );
  }

  Future<void> _deleteModel(DownloadedModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除「${model.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ModelDownloadService.deleteModelFile(model.filePath);
    await _refreshDownloaded();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型商店'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新社区列表',
            onPressed: _loadingCommunity
                ? null
                : () => _fetchCommunity(forceRefresh: true),
          ),
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: '粘贴模型链接',
            onPressed: _importFromUrl,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_resolvingRepo) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('正在解析仓库文件清单…',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.primary)),
                  const SizedBox(height: 12),
                ],
                if (_partials.isNotEmpty) ...[
                  Text('未完成的下载',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                  for (final partial in _partials)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.pause_circle_outline,
                            color: AppColors.warning),
                        title: Text(partial.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(
                          partial.resumable
                              ? '已下载 ${partial.receivedLabel} · 可断点续传'
                              : '已下载 ${partial.receivedLabel} · 缺少来源信息，仅可删除',
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (partial.resumable)
                              IconButton(
                                icon: const Icon(Icons.play_arrow,
                                    color: AppColors.primary),
                                tooltip: '继续下载',
                                onPressed: () => _resumePartial(partial),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.error),
                              tooltip: '删除',
                              onPressed: () => _deletePartial(partial),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                ],
                if (_downloaded.isNotEmpty) ...[
                  Text('已下载', style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: secondary)),
                  const SizedBox(height: 8),
                  for (final model in _downloaded)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.memory, color: AppColors.success),
                        title: Text(model.name,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('点击开始对话 · ${model.sizeMb}',
                            style: TextStyle(fontSize: 12, color: secondary)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline,
                                  color: AppColors.primary),
                              tooltip: '开始对话',
                              onPressed: () => _openChat(model),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.error),
                              onPressed: () => _deleteModel(model),
                            ),
                          ],
                        ),
                        onTap: () => _openChat(model),
                      ),
                    ),
                  const Divider(height: 24),
                  Text('可下载模型',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                ],
                for (final model in LocalModelCatalog.builtin)
                  _buildModelCard(model),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('社区模型',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: secondary)),
                    const Spacer(),
                    if (_loadingCommunity)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final model in _communityModels)
                  _buildModelCard(model),
                if (_communityModels.isEmpty && !_loadingCommunity)
                  Center(
                    child: Text('社区模型加载失败或无结果',
                        style: TextStyle(
                            fontSize: 12, color: secondary)),
                  ),
              ],
            ),
    );
  }

  /// 粘贴模型链接：自动解析 HF/ModelScope 页面并显示可下载的量化版本。
  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final parsed = await showDialog<ModelUrlParseResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴模型链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('支持 HuggingFace、ModelScope 页面链接或直接的 .gguf 下载链接。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'https://huggingface.co/...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                final result = ModelUrlParser.parse(text);
                Navigator.pop(dialogContext, result);
              },
              child: const Text('解析')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (parsed == null || parsed.isEmpty) return;

    // 仓库页面 → 拉取真实文件清单（真实文件名 + 真实大小），再让用户挑版本。
    if (parsed.repoOwner != null && parsed.repoName != null) {
      final isModelScope = parsed.source.contains('modelscope.cn');
      setState(() => _resolvingRepo = true);
      List<ModelFileVariant> files = [];
      try {
        files = isModelScope
            ? await CommunityModelService.resolveModelScopeRepo(
                '${parsed.repoOwner}/${parsed.repoName}')
            : await CommunityModelService.resolveHuggingFaceRepo(
                parsed.repoOwner!, parsed.repoName!);
      } catch (e) {
        debugPrint('[ModelStore] 解析仓库文件失败: $e');
      }
      if (!mounted) return;
      setState(() => _resolvingRepo = false);

      if (files.isEmpty) {
        messenger.showSnackBar(SnackBar(
          content: Text('未能从 ${parsed.modelName} 解析出可下载的 GGUF 文件'
              '${isModelScope ? '（魔搭仓库可能未公开文件列表）' : ''}，'
              '可在浏览器打开仓库复制具体 .gguf 文件链接后重试'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ));
        return;
      }

      final selected = await _pickVariantDialog(
        title: '${parsed.modelName} 的版本',
        modelName: parsed.modelName,
        variants: files,
        deviceSummary: _deviceRamMb != null
            ? '设备内存约 ${(_deviceRamMb! / 1024).toStringAsFixed(1)} GB'
            : null,
      );
      if (selected == null) return;
      await _downloadUrl(
        taskId: selected.fileName,
        url: selected.downloadUrl,
        fileName: selected.fileName,
        displayName: '${parsed.modelName} ${selected.quantization}',
      );
      return;
    }

    // 直接 .gguf 链接：直接下载。
    for (final url in parsed.downloadUrls) {
      final fileName = url.split('/').last;
      await _downloadUrl(
        taskId: fileName,
        url: url,
        fileName: fileName,
        displayName: parsed.modelName,
      );
    }
  }

  Widget _buildModelCard(LocalModelInfo model) {
    final download = _downloads[model.id];
    final isDownloading = download?.status == DownloadStatus.downloading;
    final isDownloaded = _downloaded.any(
        (d) => d.fileName == model.downloadUrl.split('/').last);
    // 设备内存未知时不做判断（不编造“适合你的设备”）。
    final fitsDevice = _deviceRamMb == null
        ? null
        : CommunityModelService.pickVariant(
                model.variants.isNotEmpty
                    ? model.variants
                    : [
                        ModelFileVariant(
                          fileName: model.name,
                          downloadUrl: model.downloadUrl,
                          sizeBytes: model.sizeBytes,
                          quantization: model.quantization,
                        ),
                      ],
                deviceRamMb: _deviceRamMb) !=
            null;

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
                  child: Text(model.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (model.recommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('推荐',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.success)),
                  ),
                if (fitsDevice != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (fitsDevice
                              ? AppColors.primary
                              : AppColors.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      fitsDevice ? '适合你的设备' : '可能内存不足',
                      style: TextStyle(
                          fontSize: 10,
                          color: fitsDevice
                              ? AppColors.primary
                              : AppColors.error),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(model.description,
                style: const TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 6),
            Text(
                '${model.sizeMb} · ${model.ramRequired} · ${model.quantization}'
                '${model.variants.length > 1 ? ' · ${model.variants.length} 个版本可选' : ''}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            if (isDownloading && download != null) ...[
              LinearProgressIndicator(
                value: download.fraction,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      download.totalBytes > 0
                          ? '${(download.receivedBytes / (1024 * 1024)).toStringAsFixed(0)} / ${(download.totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
                          : '连接中...',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ),
                  // 暂停按钮：已下载部分保留在 .part，可断点续传。
                  IconButton(
                    icon: const Icon(Icons.pause_circle_outline, size: 20),
                    tooltip: '暂停下载',
                    onPressed: () => _downloader.cancel(model.id),
                  ),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          isDownloaded ? null : () => _startDownload(model),
                      icon: Icon(isDownloaded ? Icons.check : Icons.download),
                      label: Text(isDownloaded ? '已下载' : '下载模型'),
                    ),
                  ),
                  if (model.variants.length > 1) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _chooseVariant(model),
                      child: const Text('选择版本'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
