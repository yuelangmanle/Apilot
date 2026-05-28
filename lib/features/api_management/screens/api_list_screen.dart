import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/api_provider.dart';
import '../widgets/api_card.dart';
import '../../../shared/theme/color_scheme.dart';

class ApiListScreen extends StatefulWidget {
  const ApiListScreen({super.key});

  @override
  State<ApiListScreen> createState() => _ApiListScreenState();
}

class _ApiListScreenState extends State<ApiListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ApiProvider>().loadApiConfigs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API管理器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
        ],
      ),
      body: Consumer<ApiProvider>(
        builder: (context, provider, child) {
          if (provider.apiConfigs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.api, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    '还没有API配置',
                    style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '点击右下角按钮添加',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.apiConfigs.length,
            itemBuilder: (context, index) {
              final api = provider.apiConfigs[index];
              return ApiCard(
                api: api,
                onTap: () {
                  // TODO: Navigate to detail screen
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
                          },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to add screen
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
