import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/import_export_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/update_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/history_screen.dart';
import '../../api_management/providers/api_provider.dart';
import '../../sync/screens/sync_screen.dart';
import '../../api_management/screens/group_manage_screen.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UpdateService _updateService = UpdateService();
  String _currentVersion = '';
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    final version = await _updateService.getCurrentVersion();
    setState(() {
      _currentVersion = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                title: const Text('导出配置'),
                subtitle: const Text('将API配置导出为JSON文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportConfigs(context),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('导入配置'),
                subtitle: const Text('从JSON文件导入API配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _importConfigs(context),
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
                    MaterialPageRoute(builder: (context) => const GroupManageScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '设备同步',
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('设备同步'),
                subtitle: const Text('通过局域网同步API配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SyncScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context: context,
            title: '历史记录',
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('请求历史'),
                subtitle: const Text('查看API测试历史记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HistoryScreen()),
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
                subtitle: const Text('允许通过蓝牙同步数据'),
                value: settings.bluetoothSync,
                onChanged: (_) => settings.toggleBluetoothSync(),
                secondary: const Icon(Icons.bluetooth),
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
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('版本'),
                subtitle: Text('v$_currentVersion'),
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
                onTap: _isCheckingUpdate ? null : () => _checkForUpdate(context),
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
                title: Text('开发者'),
                subtitle: Text('Apilot Team'),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('GitHub'),
                subtitle: const Text('github.com/yuelangmanle/Apilot'),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'https://github.com/yuelangmanle/Apilot'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('GitHub 链接已复制'), duration: Duration(seconds: 1)),
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

  Future<void> _checkForUpdate(BuildContext context) async {
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final updateInfo = await _updateService.checkForUpdate();

      if (!mounted) return;

      setState(() {
        _isCheckingUpdate = false;
      });

      if (updateInfo != null) {
        _showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('发现新版本'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
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
                  color: Colors.grey.withOpacity(0.1),
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
              _updateService.downloadUpdate(updateInfo.downloadUrl);
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

  Future<void> _exportConfigs(BuildContext context) async {
    try {
      final databaseService = DatabaseService();
      await databaseService.initialize();
      final configs = await databaseService.getAllApiConfigs();
      await databaseService.close();

      final importExportService = ImportExportService();
      final json = await importExportService.exportConfigs(configs, []);
      await importExportService.saveToFile(json, 'api_configs_export.json');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已导出到 Documents 目录'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _importConfigs(BuildContext context) async {
    try {
      final importExportService = ImportExportService();
      final databaseService = DatabaseService();
      await databaseService.initialize();

      final directory = await importExportService.getDefaultExportDirectory();
      final filePath = '$directory/api_configs_export.json';
      
      final jsonString = await importExportService.loadFromFile(filePath);
      final result = await importExportService.importConfigs(jsonString);
      
      final configs = result['apiConfigs'] as List<dynamic>;
      
      for (final config in configs) {
        await databaseService.insertApiConfig(config);
      }
      
      await databaseService.close();
      
      if (context.mounted) {
        context.read<ApiProvider>().loadApiConfigs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入 ${configs.length} 个API配置'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
