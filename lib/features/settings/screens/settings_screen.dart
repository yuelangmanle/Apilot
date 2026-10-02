import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/import_export_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/update_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../api_management/providers/api_provider.dart';
import '../../api_management/screens/group_manage_screen.dart';
import '../../third_party_import/screens/third_party_import_docs_screen.dart';
import '../../third_party_import/screens/third_party_interop_audit_screen.dart';
import 'release_history_screen.dart';
import 'ai_settings_screen.dart';
import 'gateway_screen.dart';
import '../../local_llm/screens/model_store_screen.dart';
import 'privacy_screen.dart';
import 'security_dashboard_screen.dart';
import 'usage_stats_screen.dart';
import '../../api_management/screens/recycle_bin_screen.dart';
import '../../security/app_lock_controller.dart';
import '../../security/biometric_service.dart';
import '../../security/pin_screen.dart';
import '../providers/settings_provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/group.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UpdateService _updateService = UpdateService();
  String _currentVersion = '';
  bool _isCheckingUpdate = false;
  bool _isImporting = false;
  bool _biometricAvailable = false;

  bool get _lockEnabled => context.read<AppLockController>().enabled;

  String get _biometricSubtitle {
    final lock = context.watch<AppLockController>();
    if (!lock.enabled) return '先开启应用锁';
    if (!_biometricAvailable) return '当前设备不支持或未录入指纹/面容';
    return '解锁时可用系统指纹或面容代替 PIN';
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    _detectBiometric();
  }

  Future<void> _detectBiometric() async {
    final available = await BiometricService.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  Future<void> _loadCurrentVersion() async {
    final version = await _updateService.getCurrentVersion();
    if (!mounted) return;
    setState(() {
      _currentVersion = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _buildSection(
            context: context,
            title: '数据管理',
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('备份数据'),
                subtitle: const Text('将所有API配置备份为JSON文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportConfigs(context),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('恢复数据'),
                subtitle: const Text('从备份文件恢复API配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _importConfigs(context),
              ),
              ListTile(
                leading: const Icon(Icons.insights),
                title: const Text('用量统计'),
                subtitle: const Text('按配置查看 token 消耗与请求数'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const UsageStatsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.recycling),
                title: const Text('回收站'),
                subtitle: const Text('删除的方案保留一段时间，可随时恢复'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RecycleBinScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('第三方交互记录'),
                subtitle: const Text('查看本地导入与对外授权记录，不包含密钥内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const ThirdPartyInteropAuditScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '安全',
            children: [
              SwitchListTile(
                title: const Text('应用锁'),
                subtitle: const Text('启动或从后台返回时需要输入 PIN'),
                value: context.watch<AppLockController>().enabled,
                onChanged: (_) => _toggleAppLock(),
                secondary: const Icon(Icons.lock_outline),
              ),
              SwitchListTile(
                title: const Text('指纹/面容解锁'),
                subtitle: Text(_biometricSubtitle),
                value: context.watch<AppLockController>().biometricEnabled,
                onChanged: _lockEnabled ? (_) => _toggleBiometric() : null,
                secondary: const Icon(Icons.fingerprint),
              ),
              ListTile(
                leading: const Icon(Icons.psychology),
                title: const Text('本地模型'),
                subtitle: const Text('下载并离线运行开源大模型'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ModelStoreScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('本地网关'),
                subtitle: const Text('把 Apilot 配置暴露为 127.0.0.1 的 OpenAI 兼容端点'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const GatewayScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('AI 设置'),
                subtitle: const Text('选择 AI 功能使用的引擎和配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AiSettingsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('安全仪表盘'),
                subtitle: const Text('明文端点、Key 复用等本地规则体检'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const SecurityDashboardScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('数据与安全'),
                subtitle: const Text('了解密钥存储、同步与隐私保护机制'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const PrivacyScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '分组管理',
            children: [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('分组管理'),
                subtitle: const Text('创建和管理API分组'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const GroupManageScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '同步设置',
            children: [
              SwitchListTile(
                title: const Text('自动发现设备'),
                subtitle: const Text('在同一网络下自动发现其他设备'),
                value: settings.autoDiscovery,
                onChanged: (_) => settings.toggleAutoDiscovery(),
                secondary: const Icon(Icons.wifi_find),
              ),
              SwitchListTile(
                title: const Text('蓝牙同步'),
                subtitle: const Text('通过蓝牙直接发现并传输配置，双方确认后才发送'),
                value: settings.bluetoothSync,
                onChanged: (_) => settings.toggleBluetoothSync(),
                secondary: const Icon(Icons.bluetooth_searching),
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '外观',
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('主题'),
                subtitle: Text(switch (settings.themeMode) {
                  ApilotThemeMode.system => '跟随系统',
                  ApilotThemeMode.light => '亮色',
                  ApilotThemeMode.dark => '暗色',
                }),
                trailing: SegmentedButton<ApilotThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ApilotThemeMode.system,
                        label: Text('系统'),
                        icon: Icon(Icons.brightness_auto, size: 16)),
                    ButtonSegment(
                        value: ApilotThemeMode.light,
                        label: Text('亮'),
                        icon: Icon(Icons.light_mode, size: 16)),
                    ButtonSegment(
                        value: ApilotThemeMode.dark,
                        label: Text('暗'),
                        icon: Icon(Icons.dark_mode, size: 16)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) =>
                      settings.setThemeMode(selection.first),
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '开发者',
            children: [
              ListTile(
                leading: const Icon(Icons.integration_instructions),
                title: const Text('第三方接入文档'),
                subtitle: const Text('导入配置或授权其他Android App使用本地方案'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ThirdPartyImportDocsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('版本'),
                subtitle: Text('v$_currentVersion'),
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('更新日志'),
                subtitle: const Text('查看所有已发布版本的更新内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReleaseHistoryScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  _isCheckingUpdate ? Icons.refresh : Icons.system_update,
                  color: _isCheckingUpdate ? Colors.grey : null,
                ),
                title: const Text('检查更新'),
                subtitle: Text(_isCheckingUpdate ? '正在检查...' : '检查是否有新版本'),
                trailing: _isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _isCheckingUpdate ? null : _checkForUpdate,
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('开源许可'),
                onTap: () {
                  showLicensePage(context: context);
                },
              ),
              const ListTile(
                leading: Icon(Icons.developer_mode),
                title: Text('开发人员'),
                subtitle: Text('月亮满了  |  QQ：3335196397'),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('GitHub'),
                subtitle: const Text('github.com/yuelangmanle/Apilot'),
                onTap: () {
                  Clipboard.setData(const ClipboardData(
                      text: 'https://github.com/yuelangmanle/Apilot'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('GitHub 链接已复制'),
                        duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkPrimary : AppColors.primary,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Future<void> _toggleBiometric() async {
    final lock = context.read<AppLockController>();
    final target = !lock.biometricEnabled;
    if (target) {
      // 开启前先用一次系统认证确认是本人操作。
      final ok = await BiometricService.authenticate();
      if (!mounted) return;
      if (!ok) return;
    }
    await lock.setBiometricEnabled(target);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(target ? '生物识别解锁已开启' : '生物识别解锁已关闭'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleAppLock() async {
    final lock = context.read<AppLockController>();
    if (lock.enabled) {
      // 关闭前先验证 PIN（解锁成功才会走到这里之后）。
      final unlocked = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (context) => const PinScreen(mode: PinScreenMode.unlock)),
      );
      if (unlocked == true) {
        await lock.disable();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('应用锁已关闭')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN 验证未通过，应用锁保持开启')),
        );
      }
      return;
    }
    final enabled = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) =>
              const PinScreen(mode: PinScreenMode.setFirst)),
    );
    if (mounted && enabled == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('应用锁已开启'), backgroundColor: AppColors.success),
      );
    }
  }

  /// 导出：可选口令加密备份文件。返回 null 表示不加密。
  Future<String?> _askBackupPassword(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('备份口令（可选）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置口令后备份文件将整包加密，'
                '恢复时必须输入同一口令。留空则不加密。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '口令（留空不加密）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('不加密')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text),
              child: const Text('加密并保存')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// 导入加密备份时索要口令。
  Future<String?> _askDecryptionPassword(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加密备份'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '备份口令',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text),
              child: const Text('确定')),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<void> _checkForUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isCheckingUpdate = true;
    });

    final result = await _updateService.checkForUpdate();

    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
    });

    switch (result.status) {
      case UpdateCheckStatus.updateAvailable:
        _showUpdateDialog(context, result.update!);
        break;
      case UpdateCheckStatus.upToDate:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本'),
            backgroundColor: AppColors.success,
          ),
        );
        break;
      case UpdateCheckStatus.checkFailed:
      case UpdateCheckStatus.noPackageForPlatform:
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? '检查更新失败'),
            backgroundColor: AppColors.error,
          ),
        );
        break;
    }
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: AppColors.primary),
            SizedBox(width: 8),
            Text('发现新版本'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${updateInfo.version}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  updateInfo.releaseNotes,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '发布于: ${updateInfo.publishedAt.toString().substring(0, 19)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后再说'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _startDownload(updateInfo.downloadUrl);
            },
            icon: const Icon(Icons.download),
            label: const Text('立即下载'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(String downloadUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _updateService.downloadUpdate(downloadUrl);
      messenger.showSnackBar(
        const SnackBar(content: Text('已打开下载页面')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('无法打开下载链接: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _exportConfigs(BuildContext context) async {
    try {
      // 备份文件包含明文 API Key，先让用户知情。
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('备份包含明文密钥'),
          content: const Text(
              '备份文件将以明文形式包含所有 API Key。\n\n请将备份文件保存在安全的位置，'
              '不要通过不受信任的渠道传输。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续备份'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final databaseService = DatabaseService();
      final configs = await databaseService.getAllApiConfigs();
      final groups = await databaseService.getAllGroups();

      final importExportService = ImportExportService();
      if (!context.mounted) return;
      final password = await _askBackupPassword(context);
      if (!context.mounted) return;
      final json = await importExportService.exportConfigs(configs, groups,
          password: password);
      final timestamp = DateTime.now()
          .toString()
          .substring(0, 19)
          .replaceAll(':', '-')
          .replaceAll(' ', '_');
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '选择备份保存位置',
        fileName: 'apilot_backup_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (savedPath == null) return;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已备份 ${configs.length} 个 API 和 ${groups.length} 个分组'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _importConfigs(BuildContext context) async {
    if (_isImporting) return;
    _isImporting = true;
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 Apilot 备份文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: true,
      );
      final bytes = selection?.files.single.bytes;
      if (bytes == null) return;
      final jsonString = utf8.decode(bytes).trim();
      if (jsonString.isEmpty) throw const FormatException('备份文件为空');

      final importExportService = ImportExportService();
      // 自动识别加密包：首次尝试无口令，失败提示输入口令重试。
      Map<String, dynamic> result;
      try {
        result = await importExportService.importConfigs(jsonString);
      } catch (e) {
        if (!e.toString().contains('加密')) rethrow;
        if (!context.mounted) return;
        final password = await _askDecryptionPassword(context);
        if (password == null) return;
        result = await importExportService.importConfigs(jsonString,
            password: password);
      }
      final configs = result['apiConfigs'] as List<ApiConfig>;
      final groups = result['groups'] as List<Group>;
      final exportedAt = result['exportedAt'] as DateTime?;
      if (!context.mounted) return;
      final replaceExisting = await _chooseRestoreMode(
        context,
        configCount: configs.length,
        groupCount: groups.length,
        exportedAt: exportedAt,
      );
      if (replaceExisting == null) return;

      final databaseService = DatabaseService();
      final summary = await databaseService.restoreBackup(
        configs: configs,
        groups: groups,
        replaceExisting: replaceExisting,
      );

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final apiProvider = context.read<ApiProvider>();
      await apiProvider.loadApiConfigs();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '已恢复 ${summary.configsRestored} 个 API 和 ${summary.groupsRestored} 个分组'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      _isImporting = false;
    }
  }

  Future<bool?> _chooseRestoreMode(
    BuildContext context, {
    required int configCount,
    required int groupCount,
    required DateTime? exportedAt,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复数据'),
        content: Text(
          '备份时间：${exportedAt == null ? '未记录' : exportedAt.toLocal().toString().substring(0, 19)}\n'
          '备份包含 $configCount 个 API 和 $groupCount 个分组。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('合并恢复'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('清空后恢复'),
          ),
        ],
      ),
    );
  }
}
