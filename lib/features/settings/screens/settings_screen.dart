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
import 'privacy_screen.dart';
import 'usage_stats_screen.dart';
import '../../security/app_lock_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
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
              SwitchListTile(
                title: const Text('暗黑模式'),
                subtitle: const Text('切换深色主题'),
                value: settings.isDarkMode,
                onChanged: (_) => settings.toggleDarkMode(),
                secondary: const Icon(Icons.dark_mode),
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
      final json = await importExportService.exportConfigs(configs, groups);
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
      final result = await importExportService.importConfigs(jsonString);
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
