import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../widgets/api_card.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'api_form_screen.dart';
import 'api_detail_screen.dart';
import 'template_screen.dart';

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
      if (mounted) context.read<ApiProvider>().loadApiConfigs();
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
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索API...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: isDark ? AppColors.darkTextSecondary : Colors.white70),
                ),
                style: TextStyle(color: isDark ? AppColors.darkTextPrimary : Colors.white),
                onChanged: (value) => context.read<ApiProvider>().setSearchQuery(value),
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
        ],
      ),
      body: Consumer<ApiProvider>(
        builder: (context, provider, child) {
          if (provider.apiConfigs.isEmpty && !provider.showFavoritesOnly && provider.selectedGroup == null) {
            return _buildEmptyState(context, isDark);
          }

          final content = Column(
            children: [
              _buildFilterBar(context, provider),
              Expanded(
                child: provider.apiConfigs.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的API',
                          style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => provider.loadApiConfigs(),
                        child: ListView.builder(
                          itemCount: provider.apiConfigs.length,
                          itemBuilder: (context, index) {
                            final api = provider.apiConfigs[index];
                            return ApiCard(
                              api: api,
                              onTap: () async {
                                final result = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(builder: (context) => ApiDetailScreen(apiConfig: api)),
                                );
                                if (result == true && mounted) provider.loadApiConfigs();
                              },
                              onFavoriteToggle: () {
                                provider.updateApiConfig(api.copyWith(isFavorite: !api.isFavorite));
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
                      ),
              ),
            ],
          );

          if (isWide) return CenteredContent(maxWidth: 700, child: content);
          return content;
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('添加API'),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, ApiProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = provider.availableGroups;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('收藏'),
              selected: provider.showFavoritesOnly,
              onSelected: (_) => provider.toggleFavoritesOnly(),
              avatar: Icon(
                provider.showFavoritesOnly ? Icons.star : Icons.star_border,
                size: 18,
              ),
              selectedColor: AppColors.warning.withValues(alpha: 0.2),
              checkmarkColor: AppColors.warning,
            ),
            const SizedBox(width: 8),
            if (provider.selectedGroup != null)
              FilterChip(
                label: Text(provider.selectedGroup!),
                selected: true,
                onSelected: (_) => provider.setSelectedGroup(null),
                onDeleted: () => provider.setSelectedGroup(null),
                selectedColor: AppColors.primary.withValues(alpha: 0.2),
              ),
            ...groups.where((g) => g != provider.selectedGroup).map((group) {
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  label: Text(group),
                  selected: false,
                  onSelected: (_) => provider.setSelectedGroup(group),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.api, size: 64, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('还没有API配置', style: TextStyle(fontSize: 18, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('点击下方按钮添加', style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
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
              onTap: () { Navigator.pop(context); _navigateToForm(context); },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
              title: const Text('从模板创建'),
              subtitle: const Text('选择常用API模板快速配置'),
              onTap: () { Navigator.pop(context); _navigateToTemplate(context); },
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
        builder: (context) => apiConfig != null
            ? ApiFormScreen(apiConfig: apiConfig, isEditing: true)
            : const ApiFormScreen(),
      ),
    );
    if (result == true && mounted) provider.loadApiConfigs();
  }

  Future<void> _navigateToTemplate(BuildContext context) async {
    final navigator = Navigator.of(context);
    final provider = context.read<ApiProvider>();
    final result = await navigator.push<bool>(
      MaterialPageRoute(builder: (context) => const TemplateScreen()),
    );
    if (result == true && mounted) provider.loadApiConfigs();
  }
}
