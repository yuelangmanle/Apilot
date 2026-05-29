import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/import_export_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/history_screen.dart';
import '../../api_management/providers/api_provider.dart';
import '../../sync/screens/sync_screen.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
              const ListTile(
                leading: Icon(Icons.info),
                title: Text('版本'),
                subtitle: Text('1.0.0'),
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
                subtitle: Text('API Manager Team'),
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

      // 尝试从默认导出目录加载
      final directory = await importExportService.getDefaultExportDirectory();
      final filePath = '$directory/api_configs_export.json';
      
      final jsonString = await importExportService.loadFromFile(filePath);
      final result = await importExportService.importConfigs(jsonString);
      
      final configs = result['apiConfigs'] as List<dynamic>;
      
      for (final config in configs) {
        await databaseService.insertApiConfig(config);
      }
      
      await databaseService.close();
      
      // 刷新 API 列表
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
