import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/api_templates.dart';
import '../../../core/models/api_config.dart';
import '../services/template_catalog_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../providers/api_provider.dart';
import 'api_form_screen.dart';

class TemplateScreen extends StatefulWidget {
  const TemplateScreen({super.key});

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

class _TemplateScreenState extends State<TemplateScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  TemplateCatalog? _catalog;
  bool _loadingCatalog = true;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await TemplateCatalogService.loadCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loadingCatalog = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ApiConfig> get _filteredTemplates {
    final all = _catalog == null
        ? ApiTemplates.templates
        : [..._catalog!.builtin, ..._catalog!.community];
    if (_searchQuery.isEmpty) return all;
    final query = _searchQuery.toLowerCase();
    return all.where((t) {
      return t.name.toLowerCase().contains(query) ||
          t.baseUrl.toLowerCase().contains(query) ||
          t.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  bool _isAlreadyAdded(ApiConfig template, List<ApiConfig> existing) {
    return existing.any((c) => c.baseUrl.trim() == template.baseUrl.trim());
  }

  @override
  Widget build(BuildContext context) {
    final templates = _filteredTemplates;
    final isWide = ResponsiveLayout.isWide(context);
    final existingConfigs = context.watch<ApiProvider>().apiConfigs;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索模板（名称、地址、标签）...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        if (_loadingCatalog)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: templates.isEmpty
              ? const Center(child: Text('没有匹配的模板', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    final added = _isAlreadyAdded(template, existingConfigs);
                    return _buildTemplateCard(context, template, added);
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('选择API模板')),
      body: isWide ? CenteredContent(maxWidth: 600, child: content) : content,
    );
  }

  Widget _buildTemplateCard(BuildContext context, ApiConfig template, bool added) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: added ? AppColors.success.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(added ? Icons.check_circle : Icons.api, color: added ? AppColors.success : AppColors.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(template.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (template.tags.contains('community')) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('社区',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.primaryText)),
                    ),
                  ],
                ],
              ),
            ),
            if (added)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: const Text('已添加', style: TextStyle(fontSize: 11, color: AppColors.success)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.baseUrl, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: template.tags.take(3).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(tag, style: const TextStyle(fontSize: 10, color: AppColors.secondaryText)),
                );
              }).toList(),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ApiFormScreen(apiConfig: template)),
          );
          if (result == true && context.mounted) {
            Navigator.pop(context, true);
          }
        },
      ),
    );
  }
}
