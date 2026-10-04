import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/lazy_indexed_stack.dart';
import 'shared/widgets/responsive_layout.dart';
import 'core/services/api_key_cipher.dart';
import 'core/services/cost_estimator.dart';
import 'core/services/database_service.dart';
import 'core/services/secret_store.dart';
import 'core/services/screenshot_storage.dart';
import 'features/api_management/providers/api_provider.dart';
import 'features/api_testing/providers/history_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/api_management/screens/api_list_screen.dart';
import 'features/api_testing/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/sync/screens/sync_screen.dart';
import 'features/security/app_lock_controller.dart';
import 'features/sync/services/sync_service.dart';
import 'features/security/pin_screen.dart';
import 'features/api_management/screens/api_form_screen.dart';
import 'features/api_management/screens/api_detail_screen.dart';
import 'features/api_management/services/api_connection_paste_parser.dart';
import 'features/third_party_import/models/third_party_import_models.dart';
import 'features/third_party_import/services/share_channel.dart';
import 'features/third_party_import/screens/third_party_import_docs_screen.dart';
import 'features/third_party_import/screens/third_party_api_config_pick_screen.dart';
import 'dart:ui' as ui;

import 'core/services/ai/app_tools.dart';
import 'core/services/local_llm/community_model_service.dart';
import 'core/services/local_llm/download_task_store.dart';
import 'core/services/local_llm/model_download_service.dart';
import 'core/services/local_llm/model_repo_importer.dart';
import 'core/services/local_llm/local_llm_tuning.dart';
import 'core/services/local_llm/model_storage_settings.dart';
import 'core/services/ai/tool_registry.dart';
import 'core/services/usage_aggregator.dart';
import 'features/local_llm/screens/html_editor_screen.dart';
import 'features/third_party_import/screens/third_party_gateway_grant_screen.dart';
import 'features/third_party_import/services/third_party_gateway_grant_channel.dart';
import 'features/third_party_import/screens/third_party_import_source_screen.dart';
import 'features/third_party_import/services/third_party_api_config_pick_channel.dart';
import 'features/third_party_import/services/third_party_import_channel.dart';
import 'shared/utils/persisted_route.dart';
import 'features/settings/screens/gateway_screen.dart';
import 'features/settings/screens/usage_stats_screen.dart';
import 'features/settings/screens/security_dashboard_screen.dart';
import 'features/api_management/screens/recycle_bin_screen.dart';
import 'features/api_management/screens/group_manage_screen.dart';
import 'features/local_llm/screens/model_store_screen.dart';

/// AI 截屏工具抓取整棵 App 树的锚点。
final GlobalKey _rootBoundaryKey = GlobalKey();

class ApiManagerApp extends StatelessWidget {
  const ApiManagerApp({super.key});

  static Future<void> bootstrap() async {
    // 在首次打开数据库前配置加密器：存量明文 Key 会在迁移到 v4 时
    // 一次性加密；此后所有写入均为密文。
    if (DatabaseService.configuredCipher == null) {
      try {
        DatabaseService.configureCipher(await ApiKeyCipher.create(
          SecureSecretStore(),
        ));
      } catch (e) {
        // 密钥子系统故障不阻止应用启动：数据库回退明文行为。
        debugPrint('[Apilot] API Key 加密初始化失败，回退明文存储: $e');
      }
    }
  }

  /// 注册同步落库回调：WiFi 接收方在服务器路径收完配置后刷新列表。
  static void registerSyncCallbacks(BuildContext context) {
    SyncService.onServerSyncApplied = () async {
      await context.read<ApiProvider>().loadApiConfigs();
    };
  }

  /// 应用启动后静默更新 LiteLLM 远程价格表（失败不影响使用）。
  static Future<void> refreshPriceTableAfterStartup() async {
    try {
      await CostEstimator.warmRemoteCache();
      await CostEstimator.refreshRemoteTable();
    } catch (e) {
      debugPrint('[Apilot] 价格表更新失败: $e');
    }
  }

  /// 应用启动后清理超过保留期的回收站内容（保留天数由用户设置，默认 7 天）。
  static Future<void> purgeRecycleBinAfterStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final days = prefs.getInt('apilot_recycle_retention_days') ?? 7;
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final purged = await DatabaseService().purgeExpiredApiConfigs(cutoff);
      if (purged > 0) {
        debugPrint('[Apilot] 回收站自动清理了 $purged 个过期方案');
      }
    } catch (e) {
      debugPrint('[Apilot] 回收站过期清理失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ApiProvider(DatabaseService()),
        ),
        ChangeNotifierProvider(
          create: (_) => HistoryProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AppLockController(),
        ),
      ],
      child: Consumer2<SettingsProvider, AppLockController>(
        builder: (context, settings, lock, _) {
          // 应用锁通过 home 替换实现（LockGate 内部判断）：锁屏与主界面
          // 同一导航器，锁屏不可绕过、不可返回。
          return MaterialApp(
            title: 'Apilot',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: switch (settings.themeMode) {
              ApilotThemeMode.system => ThemeMode.system,
              ApilotThemeMode.light => ThemeMode.light,
              ApilotThemeMode.dark => ThemeMode.dark,
            },
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: const AppShell(),
            debugShowCheckedModeBanner: false,
            builder: (context, lockChild) {
              // 应用锁作为不透明覆盖层盖在导航器之上：
              // 导航栈（含二级页面）全程保留，解锁后原位恢复；
              // 锁屏期间覆盖层挡住全部交互与内容。
              // RepaintBoundary：供 AI 截屏工具抓取当前画面。
              return RepaintBoundary(
                key: _rootBoundaryKey,
                child: LockGate(lockChild: lockChild),
              );
            },
          );
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _tabPrefsKey = 'apilot_last_tab';
  int _selectedIndex = 0;

  /// 恢复上次停留的页面：PIN 解锁后回到离开时的位置而非主页。
  Future<void> _restoreTab() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_tabPrefsKey) ?? 0;
      if (mounted && last >= 0 && last < _screens.length) {
        setState(() => _selectedIndex = last);
      }
    } catch (_) {}
  }

  /// 恢复上次停留的二级页面：进程被杀导致路由栈丢失后重建。
  /// 锁屏覆盖层会盖在恢复出的页面上，解锁后即可看到原页面。
  Future<void> _restoreRoute() async {
    final saved = await PersistedRoute.load();
    if (!mounted || saved == null) return;
    // 历史版本可能存过 'api-detail'：不再恢复（会突然跳进某个方案详情）。
    if (saved.key == 'api-detail') {
      await PersistedRoute.clear();
      return;
    }
    try {
      final provider = context.read<ApiProvider>();
      await provider.loadApiConfigs();
      if (!mounted) return;
      Widget? screen;
      switch (saved.key) {
        case 'gateway':
          screen = const GatewayScreen();
          break;
        case 'recycle':
          screen = const RecycleBinScreen();
          break;
        case 'usage':
          screen = const UsageStatsScreen();
          break;
        case 'security-dashboard':
          screen = const SecurityDashboardScreen();
          break;
        case 'groups':
          screen = const GroupManageScreen();
          break;
        case 'api-detail':
          final matches =
              provider.allApiConfigs.where((c) => c.id == saved.value).toList();
          if (matches.isEmpty) {
            await PersistedRoute.clear();
            return;
          }
          screen = ApiDetailScreen(apiConfig: matches.first);
          break;
        default:
          await PersistedRoute.clear();
          return;
      }
      await PersistedRoute.clear();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => screen!),
      );
    } catch (e) {
      debugPrint('[Apilot] 二级页面恢复失败: $e');
      await PersistedRoute.clear();
    }
  }

  Future<void> _selectTab(int index) async {
    setState(() => _selectedIndex = index);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_tabPrefsKey, index);
    } catch (_) {}
  }

  final ThirdPartyImportChannel _thirdPartyImportChannel =
      ThirdPartyImportChannel.instance;
  final ThirdPartyApiConfigPickChannel _thirdPartyApiConfigPickChannel =
      ThirdPartyApiConfigPickChannel.instance;
  final ThirdPartyGatewayGrantChannel _gatewayGrantChannel =
      ThirdPartyGatewayGrantChannel.instance;
  StreamSubscription<String>? _shareSubscription;

  static const List<Widget> _screens = [
    ApiListScreen(),
    HistoryScreen(),
    ModelStoreScreen(),
    SyncScreen(),
    SettingsScreen(),
  ];

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.api, label: 'API'),
    _NavItem(icon: Icons.history, label: '历史'),
    _NavItem(icon: Icons.psychology, label: '模型'),
    _NavItem(icon: Icons.sync, label: '同步'),
    _NavItem(icon: Icons.settings, label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreRoute();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Platform.isAndroid) {
        // 初始化失败（如平台通道不可用）不应成为未捕获异常。
        _thirdPartyImportChannel
            .initialize(onRequest: _handleThirdPartyImportRequest)
            .catchError((Object e) => debugPrint('[Apilot] 第三方导入通道初始化失败: $e'));
        _thirdPartyApiConfigPickChannel
            .initialize(onRequest: _handleThirdPartyApiConfigPickRequest)
            .catchError((Object e) => debugPrint('[Apilot] 第三方选择通道初始化失败: $e'));
        _gatewayGrantChannel
            .initialize(onRequest: _handleGatewayGrantRequest)
            .catchError((Object e) => debugPrint('[Apilot] 网关授权通道初始化失败: $e'));
        _initAiTools();
        _initShareTarget();
      }
      ApiManagerApp.registerSyncCallbacks(context);
    });
  }

  /// 系统分享目标：其他 App 分享文本进来 → 识别 → 表单预填。
  Future<void> _initShareTarget() async {
    ShareChannel.initialize();
    _shareSubscription = ShareChannel.shareTextStream
        .listen((text) => unawaited(_handleSharedText(text)));
    try {
      final initial = await ShareChannel.getInitialShareText();
      if (initial != null && initial.trim().isNotEmpty && mounted) {
        await _handleSharedText(initial);
      }
    } catch (e) {
      debugPrint('[Apilot] 分享文本拉取失败: $e');
    }
  }

  Future<void> _handleSharedText(String text) async {
    if (!mounted) return;
    final parsed = ApiConnectionPasteParser.parse(text);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (parsed == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('分享的文本中没有识别到成对的地址和 Key'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => ApiFormScreen(initialConnection: parsed),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _saveWindowGeometry();
    }
  }

  /// 桌面端记忆窗口几何。
  Future<void> _saveWindowGeometry() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    try {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width', size.width);
      await prefs.setDouble('window_height', size.height);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    if (isWide) {
      return _buildDesktopLayout();
    }
    return _buildPhoneLayout();
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.api, size: 28),
            ),
            destinations: _navItems.map((item) {
              return NavigationRailDestination(
                icon: Icon(item.icon),
                label: Text(item.label),
              );
            }).toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            // 懒加载保活：首次进入才构建，之后零重建且状态保留。
            child: LazyIndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return Scaffold(
      body: LazyIndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: _navItems.map((item) {
          return NavigationDestination(
            icon: Icon(item.icon),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }

  Future<void> _handleThirdPartyImportRequest(
    ThirdPartyImportRequest request,
  ) async {
    if (!mounted) return;

    if (request.openDocs) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ThirdPartyImportDocsScreen(),
        ),
      );
      return;
    }

    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ThirdPartyImportSourceScreen(request: request),
      ),
    );

    if (imported == true && mounted) {
      await context.read<ApiProvider>().loadApiConfigs();
    }
  }

  /// 注册内置 AI 工具（联网搜索/抓网页/算术/存 HTML/App 查询）并注入宿主能力。
  void _initAiTools() {
    ToolRegistry.registerBuiltins();
    registerAppTools();
    // 插件开关持久化（用户逐项控制）+ 模型存储位置。
    unawaited(ToolRegistry.loadEnabledFromPrefs());
    unawaited(ToolRegistry.loadMasterEnabled());
    unawaited(LocalLlmTuning.load());
    unawaited(ModelStorageSettings.load());
    unawaited(PersistedRoute.loadEnabled());
    ToolHost.screenshot = _captureScreenForTools;
    unawaited(ScreenshotStorage.cleanupStaleTemporaryFiles());
    AppToolHost.listApis = () async {
      final configs = context.read<ApiProvider>().allApiConfigs;
      if (configs.isEmpty) return '用户还没有保存任何 API 方案。';
      final buffer = StringBuffer('共 ${configs.length} 个 API 方案：\n');
      for (final config in configs) {
        buffer.writeln('- ${config.name}｜${config.baseUrl}｜'
            '${config.models.length} 个模型｜'
            '默认 ${config.selectedModel ?? '未设置'}');
      }
      return buffer.toString();
    };
    AppToolHost.usageSummary = () async {
      final history = context.read<HistoryProvider>().history;
      final configs = context.read<ApiProvider>().allApiConfigs;
      final names = {for (final c in configs) c.id: c.name};
      final usages = UsageAggregator.byConfig(history, names: names);
      if (usages.isEmpty) return '还没有请求历史。';
      final totalTokens = usages.fold<int>(0, (sum, u) => sum + u.totalTokens);
      final buffer =
          StringBuffer('共 ${usages.length} 个配置有记录，累计 $totalTokens tokens：\n');
      for (final usage in usages.take(10)) {
        buffer.writeln('- ${usage.configName}：${usage.requestCount} 次请求，'
            '成功 ${usage.successCount}，${usage.totalTokens} tokens');
      }
      return buffer.toString();
    };
    ToolHost.searchModels = (query) async {
      final results = await Future.wait([
        CommunityModelService.fetchHuggingFaceModels(query: query, limit: 6),
        CommunityModelService.fetchModelScopeModels(query: query, limit: 6),
      ]);
      final models = [...results[0], ...results[1]];
      if (models.isEmpty) {
        return '没有搜到「$query」的 GGUF 模型（可换关键词，或确认网络可访问 HuggingFace/魔搭）';
      }
      final buffer = StringBuffer('搜索「$query」的候选（真实体积）：\n');
      for (final model in models.take(10)) {
        buffer.writeln('- ${model.id}｜${model.name}｜${model.sizeMb}｜'
            '${model.quantization}'
            '${model.tags.contains('多模态') ? '｜多模态' : ''}');
      }
      buffer.writeln('用 model_save 把选中的仓库写入「我的社区模型」（可同时下载）。');
      return buffer.toString();
    };
    ToolHost.saveModel = (repo, download) async {
      final saved = await ModelRepoImporter.importRepo(
        repo,
        deviceRamMb: null,
        download: download,
      );
      return saved;
    };
    ToolHost.downloadStatus = () async {
      final tasks = await DownloadTaskStore.list();
      if (tasks.isEmpty) return '当前没有下载任务。';
      final buffer = StringBuffer('下载任务：\n');
      for (final task in tasks.take(10)) {
        buffer.writeln('- ${task.fileName}｜${task.status}｜'
            '${task.receivedLabel}'
            '${task.totalBytes > 0 ? ' / ${task.totalLabel}' : ''}'
            '${task.error != null ? '｜${task.error}' : ''}');
      }
      return buffer.toString();
    };
    ToolHost.listDownloaded = () async {
      final files = await ModelDownloadService.listDownloadedModels();
      if (files.isEmpty) return '还没有已下载的本地模型。';
      final buffer = StringBuffer('已下载模型（可离线对话）：\n');
      for (final file in files) {
        final size = file.lengthSync();
        buffer.writeln('- ${file.uri.pathSegments.last}｜'
            '${(size / (1024 * 1024)).toStringAsFixed(0)} MB');
      }
      return buffer.toString();
    };
    // AI 触发的下载用独立下载服务：不必先打开模型商店也能下。
    ModelRepoImporter.onDownload = (url, fileName) async {
      final downloader = ModelDownloadService();
      try {
        await downloader.download(url, fileName, expectedFileName: fileName);
      } finally {
        downloader.dispose();
      }
    };
    AppToolHost.openPage = (page) async {
      if (!mounted) return 'App 未就绪';
      switch (page) {
        case 'html':
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const HtmlEditorScreen()),
          );
          break;
        case 'recycle':
          setState(() => _selectedIndex = 2);
          break;
        default:
          setState(() {
            _selectedIndex = switch (page) {
              'usage' || 'gateway' || 'settings' => 4,
              'models' => 2,
              _ => _selectedIndex,
            };
          });
      }
      return '已打开 $page 页面';
    };
  }

  /// 供 AI 截屏工具调用：抓取 App 画面并存成 PNG。
  Future<String?> _captureScreenForTools() async {
    try {
      final boundary = _rootBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 0.75);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      ToolHost.screenshotLocation =
          await ScreenshotStorage.saveToDownloads(bytes);
      return await ScreenshotStorage.saveTemporaryForModel(bytes);
    } catch (e) {
      debugPrint('[Apilot] 截屏失败: $e');
      return null;
    }
  }

  /// 第三方 App 请求"使用本地网关"：弹确认页 → 启动网关 → 回传地址与 Token。
  Future<void> _handleGatewayGrantRequest(GatewayGrantRequest request) async {
    if (!mounted) return;
    await context.read<ApiProvider>().loadApiConfigs();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ThirdPartyGatewayGrantScreen(request: request),
      ),
    );
  }

  Future<void> _handleThirdPartyApiConfigPickRequest(
    ThirdPartyApiConfigPickRequest request,
  ) async {
    if (!mounted) return;
    await context.read<ApiProvider>().loadApiConfigs();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ThirdPartyApiConfigPickScreen(request: request),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
