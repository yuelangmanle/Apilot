import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../widgets/api_card.dart';
import '../../../shared/theme/color_scheme.dart';
import 'api_form_screen.dart';
import 'api_detail_screen.dart';
import 'template_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../sync/screens/sync_screen.dart';

class ApiListScreen extends StatefulWidget {
  const ApiListScreen({super.key});

  @override
  State<ApiListScreen> createState() => _ApiListScreenState();
}

class _ApiListScreenState extends State<ApiListScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        context.read<ApiProvider>().loadApiConfigs();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索API...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: isDark ? AppColors.darkTextSecondary : Colors.white70,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? AppColors.darkTextPrimary : Colors.white,
                ),
                onChanged: (value) {
                  context.read<ApiProvider>().setSearchQuery(value);
                },
              )
            : const Text('Apilot'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  context.read<ApiProvider>().setSearchQuery('');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SyncScreen()),
              );
            },
            tooltip: '设备同步',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: Consumer<ApiProvider>(
        builder: (context, provider, child) {
          if (provider.apiConfigs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.api,
                    size: 64,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有API配置',
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '点击下方按钮添加',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('手动添加'),
                        onPressed: () => _navigateToForm(context),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('从模板创建'),
                        onPressed: () => _navigateToTemplate(context),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadApiConfigs(),
            child: ListView.builder(
              itemCount: provider.apiConfigs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildQuickActions(context);
                }
                final api = provider.apiConfigs[index - 1];
                return ApiCard(
                  api: api,
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ApiDetailScreen(apiConfig: api),
                      ),
                    );
                    if (result == true && mounted) {
                      provider.loadApiConfigs();
                    }
                  },
                  onFavoriteToggle: () {
                    provider.updateApiConfig(
                      api.copyWith(isFavorite: !api.isFavorite),
                    );
                  },
                  onDelete: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除 ${api.name} 吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () {
                              provider.deleteApiConfig(api.id);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已删除 ${api.name}')),
                              );
                            },
                            child: const Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('添加API'),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.add_circle_outline,
              label: '手动添加',
              color: primaryColor,
              onTap: () => _navigateToForm(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.auto_awesome,
              label: '从模板创建',
              color: primaryColor,
              onTap: () => _navigateToTemplate(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.sync,
              label: '设备同步',
              color: primaryColor,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SyncScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('手动添加'),
              subtitle: const Text('填写完整的API信息'),
              onTap: () {
                Navigator.pop(context);
                _navigateToForm(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
              title: const Text('从模板创建'),
              subtitle: const Text('选择常用API模板快速配置'),
              onTap: () {
                Navigator.pop(context);
                _navigateToTemplate(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: AppColors.primary),
              title: const Text('导入配置'),
              subtitle: const Text('从JSON文件导入API配置'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToForm(BuildContext context, [dynamic apiConfig]) async {
    final navigator = Navigator.of(context);
    final provider = context.read<ApiProvider>();
    final result = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (context) => ApiFormScreen(apiConfig: apiConfig),
      ),
    );
    if (result == true && mounted) {
      provider.loadApiConfigs();
    }
  }

  Future<void> _navigateToTemplate(BuildContext context) async {
    final navigator = Navigator.of(context);
    final provider = context.read<ApiProvider>();
    final result = await navigator.push<bool>(
      MaterialPageRoute(builder: (context) => const TemplateScreen()),
    );
    if (result == true && mounted) {
      provider.loadApiConfigs();
    }
  }
}
