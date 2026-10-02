import 'package:flutter/material.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_catalog.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloader.progressStream.listen((_) {
      if (mounted) setState(() {});
    });
    _refreshDownloaded();
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
      appBar: AppBar(title: const Text('模型商店')),
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
              ],
            ),
    );
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
