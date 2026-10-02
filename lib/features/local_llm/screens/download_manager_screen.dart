import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/download_task_store.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../core/services/local_llm/model_storage_settings.dart';
import '../../../core/services/storage_cleanup_service.dart';
import '../../../shared/theme/color_scheme.dart';
import 'local_chat_screen.dart';

/// 下载管理：活动任务 + 未完成（可续传）+ 已下载模型 + 存储清理。
/// 全部状态来自磁盘，重启后依然准确。
class DownloadManagerScreen extends StatefulWidget {
  final ModelDownloadService downloader;

  const DownloadManagerScreen({super.key, required this.downloader});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  final Map<String, DownloadProgress> _active = {};
  List<PartialDownload> _partials = [];
  List<DownloadTask> _tasks = [];
  List<DownloadedModel> _downloaded = [];
  StorageReport? _storage;
  bool _loading = true;
  StreamSubscription<DownloadProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    // 续传/新下载都通过同一个下载服务实例：进度实时反映在本页。
    _subscription = widget.downloader.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        if (progress.status == DownloadStatus.downloading ||
            progress.status == DownloadStatus.paused) {
          _active[progress.taskId] = progress;
        } else {
          _active.remove(progress.taskId);
        }
      });
      if (!progress.isActive) _refresh();
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final partials = await ModelDownloadService.listPartialDownloads();
    final tasks = await DownloadTaskStore.list();
    final files = await ModelDownloadService.listDownloadedModels();
    final storage = await StorageCleanupService.scan();
    if (!mounted) return;
    setState(() {
      _partials = partials;
      _tasks = tasks;
      _downloaded = files.map((f) => DownloadedModel.fromFile(f)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _storage = storage;
      _loading = false;
    });
  }

  Future<void> _resume(PartialDownload partial) async {
    if (!partial.resumable) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _active[partial.fileName] = DownloadProgress(
        taskId: partial.fileName,
        url: partial.url,
        filePath: '',
        receivedBytes: partial.receivedBytes,
        status: DownloadStatus.downloading,
      );
    });
    try {
      await widget.downloader.download(partial.url, partial.fileName,
          expectedFileName: partial.fileName);
      messenger.showSnackBar(SnackBar(
          content: Text('「${partial.fileName}」下载完成'),
          backgroundColor: AppColors.success));
    } on DownloadCancelledException {
      messenger.showSnackBar(const SnackBar(
          content: Text('已暂停，可回来继续'), duration: Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('下载失败：$e'), backgroundColor: AppColors.error));
    }
    await _refresh();
  }

  Future<void> _deletePartial(PartialDownload partial) async {
    await ModelDownloadService.deleteModelFile(partial.partialPath);
    if (mounted) setState(() {});
    await _refresh();
  }

  Future<void> _deleteModel(DownloadedModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除已下载模型？'),
        content: Text('「${model.name}」（${model.sizeMb}）将被删除，'
            '以后需要重新下载。对话记录不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ModelDownloadService.deleteModelFile(model.filePath);
    await _refresh();
  }

  void _openChat(DownloadedModel model) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LocalChatScreen(modelPath: model.filePath, modelName: model.name),
      ),
    );
  }

  /// 切换模型存储位置（可把已下载的模型一并搬过去）。
  Future<void> _changeStorageLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final isAndroid = Platform.isAndroid;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              dense: true,
              title: Text('模型存储位置',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('公共目录在系统文件管理器里能直接看到模型文件',
                  style: TextStyle(fontSize: 12)),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, size: 20),
              title: const Text('应用私有目录（默认）', style: TextStyle(fontSize: 14)),
              trailing: ModelStorageSettings.mode == 'private'
                  ? const Icon(Icons.check, size: 18, color: AppColors.success)
                  : null,
              onTap: () => Navigator.pop(sheetContext, 'private'),
            ),
            if (isAndroid)
              ListTile(
                leading: const Icon(Icons.download_outlined, size: 20),
                title: const Text('公共下载目录 Download/Apilot',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text('需要"所有文件访问"权限',
                    style: TextStyle(fontSize: 11)),
                trailing: ModelStorageSettings.mode == 'public'
                    ? const Icon(Icons.check, size: 18, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(sheetContext, 'public'),
              ),
            if (!isAndroid)
              ListTile(
                leading: const Icon(Icons.folder_open, size: 20),
                title: const Text('选择自定义目录', style: TextStyle(fontSize: 14)),
                trailing: ModelStorageSettings.mode == 'custom'
                    ? const Icon(Icons.check, size: 18, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(sheetContext, 'custom'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    var customDir = ModelStorageSettings.customDir;
    if (choice == 'custom') {
      final picked = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择模型存放目录');
      if (picked == null || picked.isEmpty) return;
      customDir = picked;
    }

    final oldDir = await ModelDownloadService.modelsDir();
    await ModelStorageSettings.setMode(choice, customDir: customDir);
    if (!mounted) return;
    final (newDir, warning) = await ModelStorageSettings.resolveDir();
    if (warning != null) {
      messenger.showSnackBar(SnackBar(
          content: Text(warning),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 5)));
      await _refresh();
      return;
    }
    if (newDir.path == oldDir.path) {
      await _refresh();
      return;
    }

    // 问一句要不要把已有模型搬过去（默认搬，避免"模型看不见了"）。
    final move = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('搬移已下载的模型？'),
        content: Text('新位置：${newDir.path}\n'
            '把已下载的模型与未完成数据搬过去后，列表会照常显示；'
            '不搬的话旧文件仍留在原目录（空间不会自动释放）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('不搬')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('搬过去')),
        ],
      ),
    );
    if (move == true) {
      final (moved, failed) = await ModelStorageSettings.moveModels(
          oldDir, newDir);
      messenger.showSnackBar(SnackBar(
        content: Text('已搬移 $moved 个文件'
            '${failed > 0 ? '，$failed 个失败（可稍后重试）' : ''}'),
        backgroundColor: failed > 0 ? AppColors.warning : AppColors.success,
      ));
    }
    await _refresh();
  }

  Future<void> _openCleanup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CleanupSheet(onDone: _refresh),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 真失败的任务（**不含手动暂停**：暂停只算"未完成"，避免同一任务
  /// 同时出现在两个区块里）。
  List<DownloadTask> get _failedTasks => _tasks
      .where((t) =>
          t.isFailed && !_active.containsKey(t.id))
      .toList();

  /// 失败任务对应的文件名集合（未完成区块据此去重）。
  Set<String> get _failedFileNames =>
      _failedTasks.map((t) => t.fileName).toSet();

  /// 失败卡片：说明原因 + 已占空间 + 重试/删除。
  Widget _buildFailedCard(DownloadTask task, Color secondary) {
    final partialExists =
        _partials.any((p) => p.fileName == task.fileName);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 18, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                if (task.url.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试', style: TextStyle(fontSize: 12)),
                    onPressed: () => _resumeTask(task),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  tooltip: '删除记录与已下载的部分',
                  onPressed: () => _deleteTask(task),
                ),
              ],
            ),
            Text(
              '${task.isFailed ? '下载失败' : '上次中断'}'
              '${task.error != null ? '：${_shortError(task.error!)}' : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.error),
            ),
            const SizedBox(height: 2),
            Text(
              '已下载 ${task.receivedLabel}'
              '${task.totalBytes > 0 ? ' / ${task.totalLabel}' : ''}'
              '${partialExists ? ' · 占用中，可续传' : ' · 未占用空间'}',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  String _shortError(String error) {
    final cleaned =
        error.replaceAll(RegExp(r'https?://\S+'), '（下载源）').trim();
    return cleaned.length > 120 ? '${cleaned.substring(0, 120)}…' : cleaned;
  }

  Future<void> _resumeTask(DownloadTask task) async {
    if (task.url.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _active[task.id] = DownloadProgress(
        taskId: task.id,
        url: task.url,
        filePath: '',
        receivedBytes: task.receivedBytes,
        totalBytes: task.totalBytes,
        status: DownloadStatus.downloading,
      );
    });
    try {
      await widget.downloader
          .download(task.url, task.id, expectedFileName: task.fileName);
      messenger.showSnackBar(SnackBar(
          content: Text('「${task.fileName}」下载完成'),
          backgroundColor: AppColors.success));
    } on DownloadCancelledException {
      messenger.showSnackBar(const SnackBar(
          content: Text('已暂停，可回来继续'), duration: Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('下载失败：${_shortError('$e')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4)));
    }
    await _refresh();
  }

  Future<void> _deleteTask(DownloadTask task) async {
    await DownloadTaskStore.remove(task.id);
    // 连带清掉磁盘上的半成品（如果存在）。
    final partial = _partials.where((p) => p.fileName == task.fileName);
    for (final item in partial) {
      await ModelDownloadService.deleteModelFile(item.partialPath);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final storage = _storage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 存储占用 ───────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pie_chart_outline,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            const Text('存储占用',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            const Spacer(),
                            Text(
                              storage == null
                                  ? ''
                                  : '共 ${StorageCleanupService.formatBytes(storage.totalBytes)}',
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (storage != null)
                          for (final category in storage.categories)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${category.title}'
                                      '${category.itemCount > 0 ? '（${category.itemCount}）' : ''}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(category.sizeLabel,
                                      style: TextStyle(
                                          fontSize: 12, color: secondary)),
                                ],
                              ),
                            ),
                        const Divider(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.folder_outlined, size: 20),
                          title: const Text('存储位置',
                              style: TextStyle(fontSize: 13)),
                          subtitle: Text(
                            ModelStorageSettings.mode == 'public'
                                ? '公共下载目录：Download/Apilot（文件管理器可见）'
                                : ModelStorageSettings.mode == 'custom'
                                    ? '自定义目录：${ModelStorageSettings.customDir}'
                                    : '应用私有目录（默认；安卓上不好直接查看）',
                            style: TextStyle(fontSize: 11, color: secondary),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _changeStorageLocation(),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openCleanup,
                            icon: const Icon(Icons.cleaning_services_outlined,
                                size: 18),
                            label: const Text('清理垃圾（可选择）'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── 正在下载 ───────────────────────────────────────────
                if (_active.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('正在下载',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                  for (final entry in _active.entries)
                    _buildActiveCard(entry.key, entry.value, secondary),
                ],

                // ── 失败 / 上次中断（持久化记录，可重试） ───────────────
                if (_failedTasks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('失败 / 中断的下载',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                  for (final task in _failedTasks)
                    _buildFailedCard(task, secondary),
                ],

                // ── 未完成（可续传） ────────────────────────────────────
                // 正在下载的任务已在上方展示，这里不再重复列出。
                if (_partials
                    .where((p) =>
                        !_active.containsKey(p.fileName) &&
                        !_failedFileNames.contains(p.fileName))
                    .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('未完成的下载',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                  for (final partial in _partials.where((p) =>
                      !_active.containsKey(p.fileName) &&
                      !_failedFileNames.contains(p.fileName)))
                    _buildPartialCard(partial, secondary),
                ],

                // ── 已下载 ────────────────────────────────────────────
                const SizedBox(height: 8),
                Text('已下载模型',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: secondary)),
                const SizedBox(height: 8),
                if (_downloaded.isEmpty)
                  Text('还没有已下载的模型',
                      style: TextStyle(fontSize: 12, color: secondary))
                else
                  for (final model in _downloaded)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.memory,
                            color: AppColors.success),
                        title: Text(model.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('${model.sizeMb} · 点击开始对话',
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
                              tooltip: '删除',
                              onPressed: () => _deleteModel(model),
                            ),
                          ],
                        ),
                        onTap: () => _openChat(model),
                      ),
                    ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildActiveCard(
      String taskId, DownloadProgress progress, Color secondary) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.downloading, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(taskId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline, size: 20),
                  tooltip: '暂停',
                  onPressed: () => widget.downloader.cancel(taskId),
                ),
              ],
            ),
            LinearProgressIndicator(
              value: progress.fraction,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 4),
            Text(
              progress.totalBytes > 0
                  ? '${StorageCleanupService.formatBytes(progress.receivedBytes)}'
                      ' / ${StorageCleanupService.formatBytes(progress.totalBytes)}'
                  : '已下载 ${StorageCleanupService.formatBytes(progress.receivedBytes)}',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartialCard(PartialDownload partial, Color secondary) {
    final active = _active[partial.fileName];
    final received = active?.receivedBytes ?? partial.receivedBytes;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pause_circle_outline,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(partial.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                if (active == null && partial.resumable)
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续下载',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _resume(partial),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  tooltip: '删除这段未完成的数据',
                  onPressed: () => _deletePartial(partial),
                ),
              ],
            ),
            if (active != null) ...[
              LinearProgressIndicator(
                value: active.fraction,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '已下载 ${StorageCleanupService.formatBytes(received)}'
              '${partial.resumable ? ' · 可断点续传' : ' · 缺少来源信息，仅可删除'}',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 清理底部弹层：逐项勾选，明确说明删什么、留什么。
class _CleanupSheet extends StatefulWidget {
  final Future<void> Function() onDone;

  const _CleanupSheet({required this.onDone});

  @override
  State<_CleanupSheet> createState() => _CleanupSheetState();
}

class _CleanupSheetState extends State<_CleanupSheet> {
  StorageReport? _report;
  final Set<String> _selected = {};
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final report = await StorageCleanupService.scan();
    if (!mounted) return;
    setState(() {
      _report = report;
      _selected
        ..clear()
        ..addAll(report.categories
            .where((c) => c.deletable && c.defaultSelected)
            .map((c) => c.key));
    });
  }

  Future<void> _run() async {
    setState(() => _working = true);
    final freed = await StorageCleanupService.clean(_selected);
    if (!mounted) return;
    setState(() => _working = false);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('已清理，释放约 ${StorageCleanupService.formatBytes(freed)}'),
      backgroundColor: AppColors.success,
    ));
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('清理垃圾',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('只清理临时与缓存数据；已下载的模型不会被动到，'
                '需要删除请在上一个页面逐个删除。',
                style: TextStyle(fontSize: 12, color: secondary)),
            const SizedBox(height: 12),
            if (report == null)
              const Center(child: CircularProgressIndicator())
            else
              for (final category in report.categories)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _selected.contains(category.key),
                  onChanged: !category.deletable
                      ? null
                      : (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(category.key);
                            } else {
                              _selected.remove(category.key);
                            }
                          }),
                  title: Row(
                    children: [
                      Expanded(
                          child: Text(category.title,
                              style: const TextStyle(fontSize: 13))),
                      Text(category.sizeLabel,
                          style:
                              TextStyle(fontSize: 12, color: secondary)),
                    ],
                  ),
                  subtitle: Text(
                    category.deletable
                        ? category.description
                        : '${category.description}（请在列表里逐个删除）',
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_working || _selected.isEmpty)
                        ? null
                        : _run,
                    icon: _working
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cleaning_services, size: 18),
                    label: Text(_working ? '清理中…' : '清理选中项'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
