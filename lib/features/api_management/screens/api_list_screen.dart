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
          if (provider.apiConfigs.isEmpty && !provider.showFavoritesOnly && provider.selectedGroup == null && provider.selectedTag == null && provider.selectedEnvironment == null) {
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
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(api.isFavorite ? '已取消收藏' : '已收藏 ${api.name}'),
                                    duration: const Duration(seconds: 1),
                                    backgroundColor: api.isFavorite ? null : AppColors.warning,
                                  ),
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
                      ),
              ),
            ],
          );

          if (isWide) return CenteredContent(maxWidth: 700, child: content);
          return content;
        },
      ),
      floatingActionButton: Padding(
        padding: isWide ? const EdgeInsets.only(left: 80) : EdgeInsets.zero,
        child: FloatingActionButton.extended(
          onPressed: () => _showAddOptions(context),
          icon: const Icon(Icons.add),
          label: const Text('添加API'),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, ApiProvider provider) {
    final groups = provider.availableGroups;
    final tags = provider.availableTags;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          SingleChildScrollView(
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
                // Sort button
                PopupMenuButton<String>(
                  onSelected: (value) => provider.setSortBy(value),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(value: 'name', checked: provider.sortBy == 'name', child: const Text('按名称排序')),
                    CheckedPopupMenuItem(value: 'created', checked: provider.sortBy == 'created', child: const Text('按创建时间')),
                    CheckedPopupMenuItem(value: 'updated', checked: provider.sortBy == 'updated', child: const Text('按更新时间')),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: Text(provider.sortBy == 'name' ? '名称' : provider.sortBy == 'created' ? '创建时间' : '更新时间'),
                  ),
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
                ...tags.where((t) => t != provider.selectedTag).take(5).map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text('#$tag'),
                      selected: false,
                      onSelected: (_) => provider.setSelectedTag(tag),
                      selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    ),
                  );
                }),
              ],
            ),
          ),
          if (provider.selectedTag != null || provider.selectedEnvironment != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (provider.selectedTag != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('标签: ${provider.selectedTag}'),
                        onDeleted: () => provider.setSelectedTag(null),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      ),
                    ),
                  if (provider.selectedEnvironment != null)
                    Chip(
                      label: Text('环境: ${provider.selectedEnvironment}'),
                      onDeleted: () => provider.setSelectedEnvironment(null),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.api, size: 72, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
            const SizedBox(height: 20),
            Text('欢迎使用 Apilot', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
            const SizedBox(height: 12),
            Text('管理你的 AI API 配置\n快速切换、测试、同步', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.auto_awesome, color: AppColors.primary),
                      title: const Text('从模板开始'),
                      subtitle: const Text('内置 19 个常用 AI API 模板，一键配置'),
                      onTap: () => _navigateToTemplate(context),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.edit, color: AppColors.secondary),
                      title: const Text('手动添加'),
                      subtitle: const Text('填写 API 地址和 Key，自定义配置'),
                      onTap: () => _navigateToForm(context),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('推荐先从模板添加一个试试', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)),
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
