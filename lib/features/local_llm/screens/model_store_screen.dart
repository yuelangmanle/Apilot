import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_capabilities.dart';
import '../../../core/services/local_llm/model_catalog.dart';
import '../../../core/services/local_llm/community_model_service.dart';
import '../../../core/services/local_llm/model_url_parser.dart';
import '../../../core/services/local_llm/model_catalog_store.dart';
import '../../../core/services/local_llm/model_repo_importer.dart';
import '../../../core/services/local_llm/model_storage_settings.dart';
import '../services/model_curator_service.dart';
import '../../../core/services/local_llm/device_capabilities.dart';
import '../../../core/services/ai/ai_service.dart';
import '../../api_management/providers/api_provider.dart';
import '../../../core/services/local_llm/download_task_store.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../shared/theme/color_scheme.dart';
import 'download_manager_screen.dart';
import 'model_plaza_screen.dart';
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
  List<File> _projectors = [];
  Map<String, String> _projectorPairs = {};
  List<LocalModelInfo> _communityModels = [];
  List<SavedModelEntry> _savedModels = [];
  final ModelCatalogStore _catalogStore = ModelCatalogStore();
  // ---- 分类筛选（厂商 / 类型 / 特性 / 来源）----
  String _vendorFilter = '全部';
  String _typeFilter = '全部'; // 全部 / 多模态 / 纯文本
  String _thinkingFilter = '全部'; // 全部 / 支持思考
  String _sourceFilter = '全部'; // 全部 / 内置 / 社区 / 我的
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
    // AI 通过插件找到的模型也在本页下载（同一条进度/续传链路）。
    ModelRepoImporter.onDownload = (url, fileName) async {
      if (!mounted) return;
      await _downloadUrl(
        taskId: fileName,
        url: url,
        fileName: fileName,
        displayName: fileName,
      );
    };
  }

  /// AI 精选：把社区列表交给 AI 挑几个并写中文介绍，结果固定到本机。
  Future<void> _curateWithAi() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_communityModels.isEmpty) {
      messenger
          .showSnackBar(const SnackBar(content: Text('社区列表还没加载好，先点右上角刷新')));
      return;
    }
    final configs = context.read<ApiProvider>().allApiConfigs;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(
                child: Text('AI 正在浏览社区模型并生成介绍…\n'
                    '（用本地模型做 AI 时可能需要一两分钟）')),
          ],
        ),
      ),
    );
    final result = await ModelCuratorService.curate(
      _communityModels,
      configs: configs,
      deviceRamMb: _deviceRamMb,
    );
    if (!mounted) return;
    Navigator.pop(context); // 关掉进度框
    if (!result.ok) {
      messenger.showSnackBar(SnackBar(
          content: Text(result.error ?? 'AI 精选失败'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 4)));
      return;
    }
    final saved = await _catalogStore.saveAll(result.entries);
    await _loadSavedModels();
    messenger.showSnackBar(SnackBar(
      content: Text('AI 精选已固定 $saved 个模型到「我的社区模型」'),
      backgroundColor: AppColors.success,
    ));
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

  Future<void> _loadSavedModels() async {
    final saved = await _catalogStore.list();
    if (mounted) setState(() => _savedModels = saved);
  }

  Future<void> _refreshDownloaded() async {
    final files = await ModelDownloadService.listDownloadedModels();
    final partials = await ModelDownloadService.listPartialDownloads();
    final projectors = await ModelDownloadService.listProjectors();
    var pairs = await ModelStorageSettings.projectorPairs();
    // 自愈：配对记录指向的投影已经不在磁盘上 → 清掉这条配对，
    // 否则条目会一直显示"投影已装"却删不掉（用户实测的卡住场景）。
    final projectorNames =
        projectors.map((f) => f.uri.pathSegments.last).toSet();
    final modelNames = files.map((f) => f.uri.pathSegments.last).toSet();
    final stale = pairs.entries
        .where((e) =>
            !modelNames.contains(e.key) || !projectorNames.contains(e.value))
        .map((e) => e.key)
        .toList();
    for (final main in stale) {
      await ModelStorageSettings.unpairProjector(main);
      pairs = await ModelStorageSettings.projectorPairs();
    }
    await _loadSavedModels();
    if (!mounted) return;
    setState(() {
      _downloaded = files.map((f) => DownloadedModel.fromFile(f)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _partials = partials;
      _projectors = projectors;
      _projectorPairs = pairs;
      _loading = false;
    });
  }

  // ================= 分类筛选 =================
  // 模型一多（内置 24 个 + 社区上百个）就是一锅粥。按厂商/类型/特性/来源
  // 四个维度切；厂商从模型名识别（社区模型名字里自带家族名，够用）。

  static const _vendorLabels = <String, List<String>>{
    '阿里 Qwen': ['qwen', 'qwq', 'ovis'],
    'Google Gemma': ['gemma'],
    'Meta Llama': ['llama'],
    'Microsoft Phi': ['phi-'],
    '面壁 MiniCPM': ['minicpm'],
    'DeepSeek': ['deepseek'],
    '智谱 GLM': ['glm-'],
    '月之暗面 Kimi': ['kimi'],
    '小米 MiMo': ['mimo-'],
    '阶跃 Spark': ['spark-', 'step-'],
    '字节 Seed': ['seed-'],
    '百度 ERNIE': ['ernie'],
    '腾讯混元': ['hunyuan'],
    'Mistral': ['mistral', 'pixtral'],
    'IBM Granite': ['granite'],
    'HuggingFace SmolVLM': ['smolvlm'],
    'NVIDIA': ['nanovlm'],
    'LiquidAI LFM2': ['lfm2'],
  };

  static String _vendorOf(String modelName) {
    final name = modelName.toLowerCase();
    for (final entry in _vendorLabels.entries) {
      if (entry.value.any(name.contains)) return entry.key;
    }
    return '其他';
  }

  static Set<String> get _vendorOptions => _vendorLabels.keys.toSet();

  bool _matchesFilters(LocalModelInfo model, {String source = '社区'}) {
    if (_sourceFilter != '全部' && _sourceFilter != source) return false;
    if (_vendorFilter != '全部' && _vendorOf(model.name) != _vendorFilter) {
      return false;
    }
    final vision = ModelCapabilities.isVisionFamily(model.name);
    if (_typeFilter == '多模态' && !vision) return false;
    if (_typeFilter == '纯文本' && vision) return false;
    final thinking = ModelCapabilities.supportsThinking(model.name);
    if (_thinkingFilter == '支持思考' && !thinking) return false;
    return true;
  }

  List<LocalModelInfo> _filterBuiltin() {
    final source = _sourceFilter == '全部' || _sourceFilter == '内置'
        ? LocalModelCatalog.builtin
        : const <LocalModelInfo>[];
    return [
      for (final m in source)
        if (_matchesFilters(m, source: '内置')) m,
    ];
  }

  List<LocalModelInfo> _filterCommunity() {
    final source = _sourceFilter == '全部' || _sourceFilter == '社区'
        ? _communityModels
        : const <LocalModelInfo>[];
    return [
      for (final m in source)
        if (_matchesFilters(m, source: '社区')) m,
    ];
  }

  List<SavedModelEntry> _filterSaved() {
    if (_sourceFilter != '全部' && _sourceFilter != '我的') return const [];
    return [
      for (final entry in _savedModels)
        if (_matchesFilters(entry.info, source: '我的')) entry,
    ];
  }

  /// 筛选条：四个紧凑下拉，横排可滚动；选中非默认值时高亮。
  Widget _buildFilterBar(Color secondary) {
    Widget chip(String label, String current, List<String> options,
        ValueChanged<String> onChanged) {
      final active = current != options.first;
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.12)
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: current,
            isDense: true,
            borderRadius: BorderRadius.circular(10),
            style: TextStyle(
                fontSize: 12, color: active ? AppColors.primary : secondary),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v == null || v == current) return;
              setState(() => onChanged(v));
            },
          ),
        ),
      );
    }

    final vendors = ['全部', ..._vendorOptions]..sort((a, b) {
        if (a == '全部') return -1;
        if (b == '全部') return 1;
        return a.compareTo(b);
      });
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('来源：$_sourceFilter', _sourceFilter, ['全部', '内置', '社区', '我的'],
            (v) => _sourceFilter = v),
        chip('类型：$_typeFilter', _typeFilter, ['全部', '多模态', '纯文本'],
            (v) => _typeFilter = v),
        chip('厂商：$_vendorFilter', _vendorFilter, vendors,
            (v) => _vendorFilter = v),
        chip('特性：$_thinkingFilter', _thinkingFilter, ['全部', '支持思考'],
            (v) => _thinkingFilter = v),
      ]),
    );
  }

  /// 下载指定文件（社区模型的多版本/内置模型共用入口）。
  ///
  /// [pairWithMain] 非空时表示这是某个主模型的视觉投影：下完记录配对，
  /// 之后打开那个模型就能自动挂上投影（名字猜不准也没关系）。
  Future<void> _downloadUrl({
    required String taskId,
    required String url,
    required String fileName,
    required String displayName,
    String? pairWithMain,
    String? projectorShareGroup,
    Future<void>? pairAfter,
  }) async {
    if (_downloads[taskId]?.isActive == true) return;
    // 跨屏去重：下载管理/别的页面已在下同一个文件时，这里直接提示而不是
    // 再起一个（服务层也会按文件名互斥兜底）。
    if (_downloader.isFileDownloading(fileName)) {
      final existing = _downloader.waitForFile(fileName);
      if (existing != null) {
        try {
          await existing;
          await _refreshDownloaded();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('「$fileName」的现有下载失败：$e'),
              backgroundColor: AppColors.error,
            ));
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('「$fileName」正在下载中，可在下载管理里查看进度'),
            duration: const Duration(seconds: 2)));
      }
      return;
    }
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
      if (pairWithMain != null && pairAfter != null) await pairAfter;
      if (pairWithMain != null) {
        final modelsDir = await ModelDownloadService.modelsDir();
        final mainFile = File('${modelsDir.path}/$pairWithMain');
        final mainComplete = mainFile.existsSync() &&
            mainFile.lengthSync() > 0 &&
            !File('${mainFile.path}.part').existsSync();
        final paired = mainComplete &&
            await ModelStorageSettings.pairProjector(
              pairWithMain,
              fileName,
              shareGroup: projectorShareGroup,
            );
        if (!paired && mounted) {
          messenger.showSnackBar(SnackBar(
            content: Text(mainComplete
                ? '投影已下载，但它已归属于其他模型：$fileName'
                : '投影已下载，但主模型尚未完整下载，因此不会标为已配对'),
            backgroundColor: AppColors.warning,
          ));
        }
      }
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
    // taskId 统一用文件名：下载管理/商店/广场对同一文件的去重才能对上。
    final fileName = model.downloadUrl.split('/').last;
    await _downloadUrl(
      taskId: fileName,
      url: model.downloadUrl,
      fileName: fileName,
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
      taskId: selected.fileName,
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
                                        borderRadius: BorderRadius.circular(4),
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
                    final configs = context.read<ApiProvider>().allApiConfigs;
                    final device = deviceSummary ??
                        (_deviceRamMb != null
                            ? '设备内存约 ${(_deviceRamMb! / 1024).toStringAsFixed(1)} GB'
                            : '设备信息未知');
                    final advice = await AiService.ask(
                      systemPrompt: '你是本地大模型部署助手。根据设备配置推荐最合适的量化版本，'
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
                        aiAdvice = advice ?? 'AI 未配置，已按设备内存给出本地推荐';
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
    // 概率性重复的根源之一：任务实际还在下载（别的入口发起），但本页
    // 拿到的是磁盘上的一次性快照，把"下载中"显示成"中断"。
    // 点继续前先问服务层，真的在跑就只提示，绝不再起一个。
    if (_downloader.isFileDownloading(partial.fileName)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「${partial.fileName}」正在下载中，无需继续'),
          duration: const Duration(seconds: 2)));
      return;
    }
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
      // 同步清掉任务记录，否则下载管理里会长期留一张空的"失败/中断"卡片。
      await DownloadTaskStore.remove(partial.fileName);
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
    final paired = _projectorPairs[model.fileName];
    final pairedOwners = paired == null
        ? const <String>[]
        : await ModelStorageSettings.projectorOwners(paired);
    await ModelDownloadService.deleteModelFile(model.filePath);
    // 清掉配对记录；只有投影没有被同一仓库的其他量化变体共用时才删除
    // 附件，避免删掉 Q4 后让仍在使用同一投影的 Q5 也失去看图能力。
    await ModelStorageSettings.unpairProjector(model.fileName);
    final projectorStillUsed =
        pairedOwners.any((owner) => owner != model.fileName);
    if (paired != null && !projectorStillUsed) {
      for (final file in _projectors) {
        if (file.uri.pathSegments.last == paired) {
          await ModelDownloadService.deleteModelFile(file.path);
        }
      }
    }
    await _refreshDownloaded();
  }

  @override
  void dispose() {
    // 复位静态下载回调：否则它一直指向已销毁的页面，AI 触发下载时会
    // 在已 dispose 的 State 上 setState。
    ModelRepoImporter.onDownload = null;
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
            icon: const Icon(Icons.travel_explore),
            tooltip: '模型广场（搜索/筛选社区模型）',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ModelPlazaScreen(
                    onDownloadRequested: (
                        {required url,
                        required fileName,
                        required displayName,
                        String? pairWithMain,
                        String? projectorShareGroup,
                        Future<void>? pairAfter}) async {
                      await _downloadUrl(
                        taskId: fileName,
                        url: url,
                        fileName: fileName,
                        displayName: displayName,
                        pairWithMain: pairWithMain,
                        projectorShareGroup: projectorShareGroup,
                        pairAfter: pairAfter,
                      );
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 精选（挑模型 + 写介绍，固定到本机）',
            onPressed: _loadingCommunity ? null : _curateWithAi,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载管理',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      DownloadManagerScreen(downloader: _downloader),
                ),
              );
              await _refreshDownloaded();
            },
          ),
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
                // ---- 分类筛选条（厂商 / 类型 / 特性 / 来源）----
                // 社区模型和内置模型都过同一套筛选；"已下载"区不筛（那是
                // 用户自己的文件，数量少）。
                _buildFilterBar(secondary),
                const SizedBox(height: 10),
                if (_resolvingRepo) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('正在解析仓库文件清单…',
                      style: TextStyle(fontSize: 12, color: AppColors.primary)),
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
                    _buildPartialCard(partial, secondary),
                  const Divider(height: 24),
                ],
                if (_downloaded.isNotEmpty) ...[
                  Text('已下载',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                  for (final model in _downloaded) _buildDownloadedTile(model),
                  const Divider(height: 24),
                  Text('可下载模型',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 8),
                ],
                for (final model in _filterBuiltin()) _buildModelCard(model),
                if (_filterBuiltin().isEmpty &&
                    _vendorFilter == '全部' &&
                    _typeFilter == '全部' &&
                    _thinkingFilter == '全部')
                  const SizedBox.shrink(),
                const SizedBox(height: 16),
                if (_orphanProjectors.isNotEmpty) ...[
                  Text('未配对的视觉投影',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: secondary)),
                  const SizedBox(height: 6),
                  Text(
                      '这些投影文件还没有归属的模型（或主模型已删除）。'
                      '投影是模型专用的，配错无法看图；确认不需要可以删掉，'
                      '每个约几百 MB。',
                      style: TextStyle(fontSize: 11, color: secondary)),
                  const SizedBox(height: 8),
                  for (final file in _orphanProjectors)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.visibility_outlined,
                            color: AppColors.warning),
                        title: Text(file.uri.pathSegments.last,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(0)} MB'
                          ' · 未配对',
                          style: TextStyle(fontSize: 11, color: secondary),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.error),
                          tooltip: '删除投影文件',
                          onPressed: () async {
                            await ModelDownloadService.deleteModelFile(
                                file.path);
                            await _refreshDownloaded();
                          },
                        ),
                      ),
                    ),
                  const Divider(height: 24),
                ],
                if (_savedModels.isNotEmpty) ...[
                  Row(
                    children: [
                      Text('我的社区模型',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: secondary)),
                      const SizedBox(width: 6),
                      Text('（AI 精选 / 粘贴固定，保存在本机）',
                          style: TextStyle(fontSize: 11, color: secondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final entry in _filterSaved())
                    _buildSavedCard(entry, secondary),
                  const Divider(height: 24),
                ],
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
                for (final model in _filterCommunity()) _buildModelCard(model),
                if (_filterCommunity().isEmpty && !_loadingCommunity)
                  Center(
                    child: Text(
                        _communityModels.isEmpty
                            ? '社区模型加载失败或无结果'
                            : '当前筛选条件下没有匹配的社区模型',
                        style: TextStyle(fontSize: 12, color: secondary)),
                  ),
              ],
            ),
    );
  }

  /// 粘贴模型链接：自动解析 HF/ModelScope 页面并显示可下载的量化版本。
  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    var pastedText = '';
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
                pastedText = text;
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

    // 一次粘贴了多个仓库（模型库/合集页）：逐个解析 → 多选 → 固定到"我的社区模型"。
    final repos = ModelCuratorService.extractRepositories(pastedText);
    if (repos.length > 1 && parsed.variants.isEmpty) {
      await _importManyRepos(repos, messenger);
      return;
    }

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

  /// 已下载模型（若有配套的视觉投影，**收在同一条目里**，点箭头展开）。
  Widget _buildDownloadedTile(DownloadedModel model) {
    final projectorName = _projectorFor(model);
    final tile = ListTile(
      leading: const Icon(Icons.memory, color: AppColors.success),
      title:
          Text(model.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '点击开始对话 · ${model.sizeMb}'
        '${projectorName != null ? ' · 视觉投影已装（可看图）' : ''}',
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 只有视觉家族的模型才需要投影：投影是模型专用的，
          // 让纯文本模型也能"套一个"只会得到加载失败与误导。
          if (_projectors.isNotEmpty &&
              projectorName == null &&
              ModelCapabilities.isVisionFamily(model.name))
            IconButton(
              icon: const Icon(Icons.link, color: AppColors.warning),
              tooltip: '配对视觉投影（仅多模态模型）',
              onPressed: () => _pairProjectorFor(model),
            ),
          IconButton(
            icon:
                const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
            tooltip: '开始对话',
            onPressed: () => _openChat(model),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => _deleteModel(model),
          ),
        ],
      ),
      onTap: () => _openChat(model),
    );
    if (projectorName == null) {
      return Card(margin: const EdgeInsets.only(bottom: 8), child: tile);
    }
    // 有投影：默认收起，点开能看到投影文件（附件式展示，不单列成模型）。
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
        leading: const Icon(Icons.memory, color: AppColors.success),
        title: Text(model.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('点击开始对话 · ${model.sizeMb} · 多模态（投影已装）',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary)),
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('视觉投影：$projectorName',
                    style: const TextStyle(fontSize: 12)),
              ),
              IconButton(
                icon: const Icon(Icons.link_off,
                    size: 18, color: AppColors.warning),
                tooltip: '解除配对（不删文件）',
                onPressed: () async {
                  await ModelStorageSettings.unpairProjector(model.fileName);
                  await _refreshDownloaded();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                tooltip: '删除投影文件（主模型保留）',
                onPressed: () async {
                  final files = await ModelDownloadService.listProjectors();
                  for (final file in files) {
                    if (file.uri.pathSegments.last == projectorName) {
                      await ModelDownloadService.deleteModelFile(file.path);
                    }
                  }
                  // 文件删了，配对记录也要清掉，否则条目继续谎报"已装"。
                  await ModelStorageSettings.unpairProjector(model.fileName);
                  await _refreshDownloaded();
                },
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline,
                    size: 18, color: AppColors.primary),
                tooltip: '开始对话',
                onPressed: () => _openChat(model),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 手动把一个投影配对给这个模型。
  ///
  /// **投影是模型专用的**：维度不匹配会被引擎拒绝（回退纯文本）。所以这里
  /// ① 把"名字能对上"的排前面并打勾；② 选不匹配的会二次确认并说明后果。
  Future<void> _pairProjectorFor(DownloadedModel model) async {
    final messenger = ScaffoldMessenger.of(context);
    final modelCore = ModelCapabilities.coreToken(model.fileName);

    bool nameMatches(File file) {
      final projectorName = file.uri.pathSegments.last.toLowerCase();
      if (modelCore.isEmpty) return false;
      return projectorName.contains(modelCore);
    }

    final sorted = List<File>.from(_projectors)
      ..sort((a, b) {
        final aMatch = nameMatches(a) ? 0 : 1;
        final bMatch = nameMatches(b) ? 0 : 1;
        return aMatch.compareTo(bMatch);
      });

    final picked = await showDialog<File>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('给「${model.name}」选择视觉投影'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '投影是模型专用的（每个模型独一份）：只有与它配套的那一个才能用。'
              '名字能对上的已排在前面。',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogContext).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary),
            ),
          ),
          for (final file in sorted)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, file),
              child: Row(
                children: [
                  Icon(
                    nameMatches(file) ? Icons.check_circle : Icons.help_outline,
                    size: 16,
                    color: nameMatches(file)
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(file.uri.pathSegments.last,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  if (nameMatches(file))
                    const Text('名字匹配',
                        style:
                            TextStyle(fontSize: 10, color: AppColors.success)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;

    // 名字对不上：二次确认（说明可能加载失败，会回退纯文本）。
    if (!nameMatches(picked)) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('这个投影可能不配套'),
          content: Text(
            '「${picked.uri.pathSegments.last}」的名字与「${model.name}」对不上，'
            '大概率不是它的投影。投影层维度必须与主模型一致，配错会导致：'
            '看图用不了（引擎会拒绝加载并回退纯文本），文本对话不受影响。\n\n'
            '确定要配对吗？',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('仍要配对')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final paired = await ModelStorageSettings.pairProjector(
        model.fileName, picked.uri.pathSegments.last);
    if (!paired) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这个投影已经配给其他主模型，不能重复挂载'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    await _refreshDownloaded();
    messenger.showSnackBar(SnackBar(
        content: Text('已配对：${model.name} ↔ ${picked.uri.pathSegments.last}'),
        backgroundColor: AppColors.success));
  }

  /// 未被任何主模型引用的投影（孤儿）：可删除，避免无声占用几百 MB。
  List<File> get _orphanProjectors {
    final referenced = <String>{};
    for (final pair in _projectorPairs.entries) {
      referenced.add(pair.value);
    }
    for (final model in _downloaded) {
      final matched = _projectorFor(model);
      if (matched != null) referenced.add(matched);
    }
    return _projectors
        .where((f) => !referenced.contains(f.uri.pathSegments.last))
        .toList();
  }

  /// 找该主模型配套的投影文件名。没有明确配对记录就保持未挂载。
  String? _projectorFor(DownloadedModel model) {
    if (!ModelCapabilities.isVisionFamily(model.name)) return null;
    final projectorName = _projectorPairs[model.fileName];
    if (projectorName == null) return null;
    return _projectors
            .any((file) => file.uri.pathSegments.last == projectorName)
        ? projectorName
        : null;
  }

  /// 未完成下载卡片：绑实时进度（续传后立刻能看到进度与已下大小）。
  Widget _buildPartialCard(PartialDownload partial, Color secondary) {
    final active = _downloads[partial.fileName];
    final received = active?.receivedBytes ?? partial.receivedBytes;
    final downloading = active?.status == DownloadStatus.downloading;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
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
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (downloading)
                  IconButton(
                    icon: const Icon(Icons.pause_circle_outline, size: 20),
                    tooltip: '暂停',
                    onPressed: () => _downloader.cancel(partial.fileName),
                  )
                else if (partial.resumable)
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续下载', style: TextStyle(fontSize: 12)),
                    onPressed: () => _resumePartial(partial),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.error),
                  tooltip: '删除未完成数据',
                  onPressed: () => _deletePartial(partial),
                ),
              ],
            ),
            if (downloading) ...[
              LinearProgressIndicator(
                value: active?.fraction ?? 0,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              downloading && (active?.totalBytes ?? 0) > 0
                  ? '${((received) / (1024 * 1024)).toStringAsFixed(0)}'
                      ' / ${((active!.totalBytes) / (1024 * 1024)).toStringAsFixed(0)} MB · 下载中'
                  : partial.resumable
                      ? '已下载 ${_formatBytes(received)} · 可断点续传'
                      : '已下载 ${_formatBytes(received)} · 缺少来源信息，仅可删除',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// 一次粘贴多个仓库：解析全部可下载文件 → 多选 → 固定到本机商店。
  Future<void> _importManyRepos(
      List<RepoRef> repos, ScaffoldMessengerState messenger) async {
    setState(() => _resolvingRepo = true);
    final resolved = <LocalModelInfo>[];
    try {
      resolved.addAll(await ModelCuratorService.resolvePastedLinks(
        repos
            .map((r) => r.host == 'modelscope'
                ? 'https://modelscope.cn/models/${r.path}'
                : 'https://huggingface.co/${r.path}')
            .join('\n'),
        deviceRamMb: _deviceRamMb,
      ));
    } catch (e) {
      debugPrint('[ModelStore] 多仓库解析失败: $e');
    }
    if (!mounted) return;
    setState(() => _resolvingRepo = false);
    if (resolved.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('这些链接里没有解析出可下载的 GGUF 文件'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    final selected = await showDialog<List<LocalModelInfo>>(
      context: context,
      builder: (dialogContext) {
        final chosen = <String>{resolved.first.id};
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text('解析到 ${resolved.length} 个模型'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('勾选后固定到「我的社区模型」，可随时下载或移除。',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final model in resolved)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: chosen.contains(model.id),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  chosen.add(model.id);
                                } else {
                                  chosen.remove(model.id);
                                }
                              }),
                              title: Text(model.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                  '${model.sizeMb} · ${model.quantization}'
                                  '${model.variants.length > 1 ? ' · ${model.variants.length} 个版本' : ''}',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext,
                    resolved.where((m) => chosen.contains(m.id)).toList()),
                child: const Text('固定到我的社区模型'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected.isEmpty) return;
    final count = await _catalogStore.saveAll(selected
        .map((m) => SavedModelEntry(
              info: m,
              source: 'paste',
              addedAt: DateTime.now(),
            ))
        .toList());
    await _loadSavedModels();
    messenger.showSnackBar(SnackBar(
      content: Text('已固定 $count 个模型到「我的社区模型」'),
      backgroundColor: AppColors.success,
    ));
  }

  /// 已固定的模型卡片：显示 AI 写的介绍、能力标签，可下载/移除。
  Widget _buildSavedCard(SavedModelEntry entry, Color secondary) {
    final model = entry.info;
    final sourceLabel = switch (entry.source) {
      'ai' => 'AI 精选',
      'paste' => '粘贴解析',
      _ => '手动',
    };
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
                Text(sourceLabel,
                    style: TextStyle(fontSize: 10, color: secondary)),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '从我的社区模型移除（不影响已下载文件）',
                  onPressed: () async {
                    await _catalogStore.delete(model.id);
                    await _loadSavedModels();
                  },
                ),
              ],
            ),
            if (model.description.isNotEmpty)
              Text(model.description,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 6),
            if (model.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final tag in model.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tag,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.primary)),
                      ),
                  ],
                ),
              ),
            Text(
                '${model.sizeMb} · ${model.ramRequired} · ${model.quantization}',
                style: TextStyle(fontSize: 11, color: secondary)),
            const SizedBox(height: 8),
            _buildModelCard(model),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(LocalModelInfo model) {
    final download = _downloads[model.downloadUrl.split('/').last];
    final isDownloading = download?.status == DownloadStatus.downloading;
    final isDownloaded =
        _downloaded.any((d) => d.fileName == model.downloadUrl.split('/').last);
    // 投影已安装要看"投影清单"（listDownloadedModels 已明确排除 mmproj，
    // 之前用它判断 → 永远显示"补装视觉投影"，点第二次会重下）。
    final modelFileName = model.downloadUrl.split('/').last;
    final projectorName = _projectorPairs[modelFileName];
    final projectorDownloadName = model.mmProjUrl == null
        ? null
        : ModelStorageSettings.scopedProjectorFileName(
            model.id, model.mmProjUrl!.split('/').last);
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('推荐',
                        style:
                            TextStyle(fontSize: 10, color: AppColors.success)),
                  ),
                if (fitsDevice != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (fitsDevice ? AppColors.primary : AppColors.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      fitsDevice ? '适合你的设备' : '可能内存不足',
                      style: TextStyle(
                          fontSize: 10,
                          color:
                              fitsDevice ? AppColors.primary : AppColors.error),
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
            if (model.mmProjUrl != null) ...[
              const SizedBox(height: 6),
              Builder(builder: (context) {
                const visionTags = ['多模态'];
                final isVision =
                    model.tags.any((t) => visionTags.contains(t)) ||
                        model.mmProjUrl != null;
                if (!isVision) return const SizedBox.shrink();
                final installed = projectorName != null &&
                    _projectors
                        .any((f) => f.uri.pathSegments.last == projectorName);
                return TextButton.icon(
                  onPressed: installed
                      ? null
                      : projectorDownloadName == null
                          ? null
                          : () => _downloadUrl(
                                taskId: projectorDownloadName,
                                url: model.mmProjUrl!,
                                fileName: projectorDownloadName,
                                displayName: '$projectorDownloadName（视觉投影）',
                                // 下载时记录"主模型↔投影"配对：之后自动挂载。
                                pairWithMain: modelFileName,
                                projectorShareGroup: model.id,
                              ),
                  icon: Icon(
                      installed ? Icons.check : Icons.visibility_outlined,
                      size: 18),
                  label: Text(
                    installed ? '视觉投影已配对 · 发图片时加载' : '补装视觉投影（下载完成后配对）',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
