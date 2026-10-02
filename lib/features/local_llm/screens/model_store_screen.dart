import 'package:flutter/material.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_catalog.dart';
import '../../../core/services/local_llm/community_model_service.dart';
import '../../../core/services/local_llm/model_url_parser.dart';
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
  List<LocalModelInfo> _communityModels = [];
  bool _loadingCommunity = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloader.progressStream.listen((_) {
      if (mounted) setState(() {});
    });
    _refreshDownloaded();
    _fetchCommunity();
  }

  Future<void> _fetchCommunity() async {
    try {
      final models = await CommunityModelService.fetchHuggingFaceModels();
      if (mounted) {
        setState(() {
          _communityModels = models;
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
    if (!mounted) return;
    setState(() {
      _downloaded = files
          .map((f) => DownloadedModel.fromFile(f))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _loading = false;
    });
  }

  Future<void> _startDownload(LocalModelInfo model) async {
    if (_downloads[model.id]?.isActive == true) return;
    setState(() {
      _downloads[model.id] = DownloadProgress(
        taskId: model.id,
        url: model.downloadUrl,
        filePath: '',
        status: DownloadStatus.downloading,
      );
    });
    try {
      await _downloader.download(
        model.downloadUrl,
        model.id,
        onProgress: (received, total) {
          // 进度由 progressStream 驱动 UI，此处无需额外处理。
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${model.name}」下载完成'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _refreshDownloaded();
    } on DownloadCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载已暂停，可重新点击继续'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _downloads.remove(model.id));
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
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型商店'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: '粘贴模型链接',
            onPressed: () => _importFromUrl(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
  Future<void> _importFromUrl(BuildContext context) async {
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

    // 解析出多个版本时让用户选择
    if (parsed.variants.isNotEmpty) {
      final selectedUrl = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('选择量化版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < parsed.downloadUrls.length; i++)
                ListTile(
                  dense: true,
                  title: Text(
                      parsed.variants.length > i
                          ? parsed.variants[i]
                          : '变体 ${i + 1}',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      parsed.downloadUrls[i].split('/').last,
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(
                      dialogContext, parsed.downloadUrls[i]),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
          ],
        ),
      );
      if (selectedUrl == null) return;
      // 下载选中的量化版本
      final fileName = selectedUrl.split('/').last;
      try {
        await _downloader.download(selectedUrl, fileName,
            expectedFileName: fileName);
        messenger.showSnackBar(
          SnackBar(
              content: Text('已下载 $fileName'),
              backgroundColor: AppColors.success),
        );
        await _refreshDownloaded();
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: AppColors.error));
      }
      return;
    }

    // 单个下载链接
    for (final url in parsed.downloadUrls) {
      try {
        await _downloader.download(url, url.split('/').last,
            expectedFileName: url.split('/').last);
        messenger.showSnackBar(
          SnackBar(
              content: Text('已下载 ${parsed.modelName}'),
              backgroundColor: AppColors.success),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('下载失败: $e'), backgroundColor: AppColors.error));
      }
    }
    await _refreshDownloaded();
  }

  Widget _buildModelCard(LocalModelInfo model) {
    final download = _downloads[model.id];
    final isDownloading = download?.status == DownloadStatus.downloading;
    final isDownloaded = _downloaded.any(
        (d) => d.fileName == model.downloadUrl.split('/').last);

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
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    QuantizationRecommender.recommend(
                            [model.quantization], ramMb: 8000) != null
                        ? '适合你的设备'
                        : '可能内存不足',
                    style: TextStyle(
                        fontSize: 10,
                        color: QuantizationRecommender.recommend(
                                [model.quantization], ramMb: 8000) != null
                            ? AppColors.primary
                            : AppColors.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(model.description,
                style: const TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 6),
            Text('${model.sizeMb} · ${model.ramRequired} · ${model.quantization}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ),
                  // 暂停/继续按钮
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    tooltip: '取消下载',
                    onPressed: () => _downloader.cancel(model.id),
                  ),
                ],
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isDownloaded ? null : () => _startDownload(model),
                  icon: Icon(isDownloaded ? Icons.check : Icons.download),
                  label: Text(isDownloaded ? '已下载' : '下载模型'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
