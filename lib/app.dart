import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/responsive_layout.dart';
import 'core/services/api_key_cipher.dart';
import 'core/services/database_service.dart';
import 'core/services/secret_store.dart';
import 'features/api_management/providers/api_provider.dart';
import 'features/api_testing/providers/history_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/api_management/screens/api_list_screen.dart';
import 'features/api_testing/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/sync/screens/sync_screen.dart';
import 'features/security/app_lock_controller.dart';
import 'features/security/pin_screen.dart';
import 'features/api_management/screens/api_form_screen.dart';
import 'features/api_management/services/api_connection_paste_parser.dart';
import 'features/third_party_import/models/third_party_import_models.dart';
import 'features/third_party_import/services/share_channel.dart';
import 'features/third_party_import/screens/third_party_import_docs_screen.dart';
import 'features/third_party_import/screens/third_party_api_config_pick_screen.dart';
import 'features/third_party_import/screens/third_party_import_source_screen.dart';
import 'features/third_party_import/services/third_party_api_config_pick_channel.dart';
import 'features/third_party_import/services/third_party_import_channel.dart';

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
          // 应用锁在 MaterialApp 外层：锁定时只渲染 PIN 输入。
          return LockGate(
            child: MaterialApp(
              title: 'Apilot',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
              home: const AppShell(),
              debugShowCheckedModeBanner: false,
            ),
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

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final ThirdPartyImportChannel _thirdPartyImportChannel =
      ThirdPartyImportChannel.instance;
  final ThirdPartyApiConfigPickChannel _thirdPartyApiConfigPickChannel =
      ThirdPartyApiConfigPickChannel.instance;
  StreamSubscription<String>? _shareSubscription;

  static const List<Widget> _screens = [
    ApiListScreen(),
    HistoryScreen(),
    SyncScreen(),
    SettingsScreen(),
  ];

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.api, label: 'API'),
    _NavItem(icon: Icons.history, label: '历史'),
    _NavItem(icon: Icons.sync, label: '同步'),
    _NavItem(icon: Icons.settings, label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Platform.isAndroid) {
        // 初始化失败（如平台通道不可用）不应成为未捕获异常。
        _thirdPartyImportChannel
            .initialize(onRequest: _handleThirdPartyImportRequest)
            .catchError((Object e) =>
                debugPrint('[Apilot] 第三方导入通道初始化失败: $e'));
        _thirdPartyApiConfigPickChannel
            .initialize(onRequest: _handleThirdPartyApiConfigPickRequest)
            .catchError((Object e) =>
                debugPrint('[Apilot] 第三方选择通道初始化失败: $e'));
        _initShareTarget();
      }
    });
  }

  /// 系统分享目标：其他 App 分享文本进来 → 识别 → 表单预填。
  Future<void> _initShareTarget() async {
    ShareChannel.initialize();
    _shareSubscription = ShareChannel.shareTextStream.listen(
        (text) => unawaited(_handleSharedText(text)));
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
  void dispose() {
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
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
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
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
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
