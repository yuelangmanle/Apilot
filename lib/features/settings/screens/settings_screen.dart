import 'package:flutter/material.dart';
import '../../../core/services/import_export_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _buildSection(
            title: '数据管理',
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file, color: AppColors.primary),
                title: const Text('导出配置'),
                subtitle: const Text('将API配置导出为JSON文件'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportConfigs(context),
              ),
              ListTile(
                leading: const Icon(Icons.download, color: AppColors.primary),
                title: const Text('导入配置'),
                subtitle: const Text('从JSON文件导入API配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _importConfigs(context),
              ),
            ],
          ),
          _buildSection(
            title: '历史记录',
            children: [
              ListTile(
                leading: const Icon(Icons.history, color: AppColors.primary),
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
            title: '同步设置',
            children: [
              SwitchListTile(
                title: const Text('自动发现设备'),
                subtitle: const Text('在同一网络下自动发现其他设备'),
                value: true,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('功能开发中...')),
                  );
                },
                secondary: const Icon(Icons.wifi_find, color: AppColors.primary),
              ),
              SwitchListTile(
                title: const Text('蓝牙同步'),
                subtitle: const Text('允许通过蓝牙同步数据'),
                value: false,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('功能开发中...')),
                  );
                },
                secondary: const Icon(Icons.bluetooth, color: AppColors.primary),
              ),
            ],
          ),
          _buildSection(
            title: '外观',
            children: [
              SwitchListTile(
                title: const Text('暗黑模式'),
                subtitle: const Text('切换深色主题'),
                value: false,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('功能开发中...')),
                  );
                },
                secondary: const Icon(Icons.dark_mode, color: AppColors.primary),
              ),
            ],
          ),
          _buildSection(
            title: '关于',
            children: [
              const ListTile(
                leading: Icon(Icons.info, color: AppColors.primary),
                title: Text('版本'),
                subtitle: Text('1.0.0'),
              ),
              ListTile(
                leading: const Icon(Icons.code, color: AppColors.primary),
                title: const Text('开源许可'),
                onTap: () {
                  showLicensePage(context: context);
                },
              ),
              const ListTile(
                leading: Icon(Icons.developer_mode, color: AppColors.primary),
                title: Text('开发者'),
                subtitle: Text('API Manager Team'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
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
      // For now, show a dialog explaining the feature
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入配置'),
          content: const Text('请将导出的 JSON 文件放在 Documents 目录下，文件名为 api_configs_export.json，然后重新打开应用。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
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
