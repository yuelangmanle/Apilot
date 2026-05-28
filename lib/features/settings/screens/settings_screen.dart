import 'package:flutter/material.dart';
import '../../../shared/theme/color_scheme.dart';

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
                leading: const Icon(Icons.upload_file),
                title: const Text('导出配置'),
                subtitle: const Text('将API配置导出为JSON文件'),
                onTap: () => _exportConfigs(context),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('导入配置'),
                subtitle: const Text('从JSON文件导入API配置'),
                onTap: () => _importConfigs(context),
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
                  // TODO: Implement auto-discovery toggle
                },
              ),
              SwitchListTile(
                title: const Text('蓝牙同步'),
                subtitle: const Text('允许通过蓝牙同步数据'),
                value: false,
                onChanged: (value) {
                  // TODO: Implement bluetooth toggle
                },
              ),
            ],
          ),
          _buildSection(
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
                  // TODO: Show licenses
                },
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
    // TODO: Implement export
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已导出')),
    );
  }

  Future<void> _importConfigs(BuildContext context) async {
    // TODO: Implement import
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已导入')),
    );
  }
}
