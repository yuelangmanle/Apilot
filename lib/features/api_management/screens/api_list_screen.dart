import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/health_check_service.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../sync/screens/qr_scanner_screen.dart';
import '../services/api_connection_paste_parser.dart';
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
  final HealthCheckService _healthService = HealthCheckService();
  bool _isHealthChecking = false;
  int _healthDone = 0;
  int _healthTotal = 0;
  Timer? _searchDebounce;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<ApiProvider>().loadApiConfigs();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('已选 ${_selectedIds.length} 项')
            : _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索API...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: isDark ? AppColors.darkTextSecondary : Colors.white70),
                ),
                style: TextStyle(color: isDark ? AppColors.darkTextPrimary : Colors.white),
                onChanged: (value) {
                  // 300ms 防抖：避免每个键击整页重建。
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    context.read<ApiProvider>().setSearchQuery(value);
                  });
                },
              )
            : const Text('Apilot'),
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '退出选择',
                  onPressed: () => setState(() {
                    _selectMode = false;
                    _selectedIds.clear();
                  }),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: _selectedIds.isEmpty ? null : AppColors.error),
                  tooltip: '删除所选',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                ),
              ]
            : [
                IconButton(
                  // 图标常驻：体检进度用角标展示，结束后可再次点击。
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.health_and_safety_outlined),
                      if (_isHealthChecking)
                        Positioned(
                          right: -6,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_healthDone/$_healthTotal',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: _isHealthChecking
                      ? '正在体检 $_healthDone/$_healthTotal，点击停止'
                      : '一键体检全部 Key',
                  onPressed: _runHealthCheck,
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量管理',
                  onPressed: () => setState(() => _selectMode = true),
                ),
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
                    ? _buildFilteredEmptyState(context, provider)
                    : RefreshIndicator(
                        onRefresh: () => provider.loadApiConfigs(),
                        child: ListView.builder(
                          itemCount: provider.apiConfigs.length,
                          itemBuilder: (context, index) {
                            final api = provider.apiConfigs[index];
                            return ApiCard(
                              api: api,
                              health: _healthService.resultFor(api.id),
                              selectMode: _selectMode,
                              selected: _selectedIds.contains(api.id),
                              onSelectToggle: () => setState(() {
                                if (_selectedIds.contains(api.id)) {
                                  _selectedIds.remove(api.id);
                                } else {
                                  _selectedIds.add(api.id);
                                }
                              }),
                              onTap: () async {
                                final result = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(builder: (context) => ApiDetailScreen(apiConfig: api)),
                                );
                                if (result == true && mounted) provider.loadApiConfigs();
                              },
                              onFavoriteToggle: () {
                                // bump updatedAt：收藏状态参与同步"新者胜"。
                                provider.updateApiConfig(api.copyWith(
                                    isFavorite: !api.isFavorite,
                                    updatedAt: DateTime.now()));
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(api.isFavorite ? '已取消收藏' : '已收藏 ${api.name}'),
                                    duration: const Duration(seconds: 1),
                                    backgroundColor: api.isFavorite ? null : AppColors.warning,
                                  ),
                                );
                              },
                              onDelete: () async {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                // 确认已在 confirmDismiss 中完成，这里直接移入回收站。
                                try {
                                  await provider.deleteApiConfig(api.id);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('已移入回收站：${api.name}'),
                                      backgroundColor: AppColors.success,
                                      duration: const Duration(seconds: 4),
                                      action: SnackBarAction(
                                        label: '撤销',
                                        onPressed: () {
                                          provider
                                              .restoreFromRecycleBin(api.id);
                                        },
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(friendlyError(e)),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
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

  Future<void> _runHealthCheck() async {
    // 体检进行中再点：停止剩余项（已完成的结果保留）。
    if (_isHealthChecking) {
      _healthService.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已停止体检，已完成的结果保留'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final provider = context.read<ApiProvider>();
    final configs = provider.allApiConfigs;
    if (configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可体检的 API 配置')),
      );
      return;
    }
    setState(() {
      _isHealthChecking = true;
      _healthDone = 0;
      _healthTotal = configs.length;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _healthService.checkAll(configs, onProgress: (done, total) {
        if (!mounted) return;
        // 每个体检完一项就刷新：健康徽标逐个出现。
        setState(() => _healthDone = done);
      });
      if (!mounted) return;
      setState(() {}); // 刷新徽标
      final dead = configs
          .where((c) =>
              _healthService.resultFor(c.id)?.status ==
              KeyHealthStatus.authFailed)
          .length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(dead == 0
              ? '体检完成：全部 ${configs.length} 个 Key 正常'
              : '体检完成：发现 $dead 个失效 Key，已标红'),
          backgroundColor: dead == 0 ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('体检失败: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isHealthChecking = false);
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final provider = context.read<ApiProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量移入回收站'),
        content: Text('选中的 $count 个 API 配置将移入回收站，保留期内可随时恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入回收站',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    var deleted = 0;
    var failed = 0;
    for (final id in _selectedIds.toList()) {
      try {
        await provider.moveToRecycleBin(id);
        deleted++;
      } catch (e) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(failed == 0
            ? '已移入回收站 $deleted 个配置'
            : '已移入回收站 $deleted 个，$failed 个失败'),
        backgroundColor: failed == 0 ? null : AppColors.error,
      ),
    );
  }

  /// 有筛选条件但结果为空时给出"清除全部筛选"的出口，避免死胡同。
  Widget _buildFilteredEmptyState(
      BuildContext context, ApiProvider provider) {
    final conditions = <String>[
      if (provider.showFavoritesOnly) '仅收藏',
      if (provider.selectedGroup != null) '分组: ${provider.selectedGroup}',
      if (provider.selectedEnvironment != null)
        '环境: ${provider.selectedEnvironment}',
      if (provider.selectedTag != null) '标签: ${provider.selectedTag}',
      if (provider.searchQuery.isNotEmpty) '搜索: ${provider.searchQuery}',
    ];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 56,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          const Text('没有匹配的API', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            '当前条件：${conditions.join(' · ')}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: provider.clearAllFilters,
            icon: const Icon(Icons.clear_all),
            label: const Text('清除全部筛选'),
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
                      subtitle: const Text('内置 28 个常用 AI API 模板，一键配置'),
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
              leading: const Icon(Icons.content_paste_search,
                  color: AppColors.primary),
              title: const Text('从剪贴板识别'),
              subtitle: const Text('复制过含地址和 Key 的文本？一键识别'),
              onTap: () {
                Navigator.pop(context);
                _addFromClipboard(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner,
                  color: AppColors.primary),
              title: const Text('扫二维码导入'),
              subtitle: const Text('扫描其他设备上的 Apilot 配置码'),
              onTap: () {
                Navigator.pop(context);
                _scanImportConfig();
              },
            ),
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

  /// 扫码导入单配置：识别 Apilot 配置码（JSON）并预填表单。
  Future<void> _scanImportConfig() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final apiProvider = context.read<ApiProvider>();
    try {
      final scanned = await navigator.push<String>(
        MaterialPageRoute(builder: (context) => const QrScannerScreen()),
      );
      if (scanned == null || scanned.isEmpty) return;
      Map<String, dynamic>? configJson;
      try {
        final decoded = jsonDecode(scanned);
        if (decoded is Map<String, dynamic> &&
            decoded['apilotConfig'] is Map) {
          configJson =
              Map<String, dynamic>.from(decoded['apilotConfig'] as Map);
        }
      } catch (_) {}
      if (configJson == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('二维码不是 Apilot 配置码'),
            backgroundColor: AppColors.warning));
        return;
      }
      final cfg = configJson;
      final parsed = ApiConnectionPasteParser.parse(
          '地址：${cfg['baseUrl'] ?? ''} Key：${cfg['apiKey'] ?? ''}');
      await navigator.push(
        MaterialPageRoute(
          builder: (context) => ApiFormScreen(
            initialConnection: parsed,
            initialName: cfg['name']?.toString(),
          ),
        ),
      );
      await apiProvider.loadApiConfigs();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  /// 主路径激活优化：FAB 直达剪贴板识别，识别结果直接预填进表单。
  Future<void> _addFromClipboard(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final apiProvider = context.read<ApiProvider>();
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      final parsed = text.trim().isEmpty
          ? null
          : ApiConnectionPasteParser.parse(text);
      if (parsed != null) {
        await navigator.push(
          MaterialPageRoute(
            builder: (context) => ApiFormScreen(initialConnection: parsed),
          ),
        );
        await apiProvider.loadApiConfigs();
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('剪贴板里没有识别到成对的地址和 Key，已打开手动添加'),
          duration: Duration(seconds: 2),
        ),
      );
      await navigator.push(
        MaterialPageRoute(builder: (context) => const ApiFormScreen()),
      );
      await apiProvider.loadApiConfigs();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.error),
      );
    }
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
