import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';

class ApiFormScreen extends StatefulWidget {
  final ApiConfig? apiConfig;

  const ApiFormScreen({super.key, this.apiConfig});

  @override
  State<ApiFormScreen> createState() => _ApiFormScreenState();
}

class _ApiFormScreenState extends State<ApiFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelsController = TextEditingController();
  final _groupController = TextEditingController();
  final _tagsController = TextEditingController();
  String _environment = 'development';
  bool _isFavorite = false;
  bool _isLoading = false;
  bool _isFetchingModels = false;

  @override
  void initState() {
    super.initState();
    if (widget.apiConfig != null) {
      final api = widget.apiConfig!;
      _nameController.text = api.name;
      _baseUrlController.text = api.baseUrl;
      _apiKeyController.text = api.apiKey;
      _modelsController.text = api.models.join(', ');
      _groupController.text = api.group ?? '';
      _tagsController.text = api.tags.join(', ');
      _environment = api.environment;
      _isFavorite = api.isFavorite;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelsController.dispose();
    _groupController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.apiConfig != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑API' : '添加API'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteApi,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'API名称 *',
                        hintText: '例如：DeepSeek',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入API名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API地址 *',
                        hintText: '例如：https://api.deepseek.com/v1',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入API地址';
                        }
                        if (!value.startsWith('http://') && !value.startsWith('https://')) {
                          return '请输入有效的URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: InputDecoration(
                        labelText: 'API Key *',
                        hintText: '输入你的API密钥',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () {
                            if (_apiKeyController.text.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: _apiKeyController.text));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制 API Key'), duration: Duration(seconds: 1)),
                              );
                            }
                          },
                        ),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入API Key';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _modelsController,
                            decoration: const InputDecoration(
                              labelText: '模型列表',
                              hintText: '用逗号分隔，或点击获取',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.smart_toy),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _isFetchingModels ? null : _fetchModels,
                            icon: _isFetchingModels 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh, size: 18),
                            label: const Text('获取'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _environment,
                      decoration: const InputDecoration(
                        labelText: '环境',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.cloud),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'development', child: Text('开发环境')),
                        DropdownMenuItem(value: 'staging', child: Text('测试环境')),
                        DropdownMenuItem(value: 'production', child: Text('生产环境')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _environment = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _groupController,
                      decoration: const InputDecoration(
                        labelText: '分组',
                        hintText: '例如：LLM、TTS',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: '标签',
                        hintText: '用逗号分隔',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('收藏'),
                      subtitle: const Text('添加到收藏夹快速访问'),
                      value: _isFavorite,
                      onChanged: (value) {
                        setState(() {
                          _isFavorite = value;
                        });
                      },
                      secondary: Icon(
                        _isFavorite ? Icons.star : Icons.star_border,
                        color: _isFavorite ? AppColors.warning : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _saveApi,
                      icon: const Icon(Icons.save),
                      label: Text(isEditing ? '保存修改' : '添加API'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _fetchModels() async {
    if (_baseUrlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写 API 地址和 API Key'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isFetchingModels = true;
    });

    try {
      final apiService = ApiService();
      final apiConfig = ApiConfig(
        id: 'temp',
        name: 'temp',
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: [],
        environment: _environment,
      );

      final models = await apiService.getAvailableModels(apiConfig);
      
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
          if (models.isNotEmpty) {
            _modelsController.text = models.join(', ');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('成功获取 ${models.length} 个模型'),
                backgroundColor: AppColors.success,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('未获取到模型，请检查地址和Key是否正确'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingModels = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('获取失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveApi() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final databaseService = DatabaseService();
      await databaseService.initialize();

      final models = _modelsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final tags = _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final api = ApiConfig(
        id: widget.apiConfig?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: models,
        environment: _environment,
        group: _groupController.text.trim().isNotEmpty ? _groupController.text.trim() : null,
        tags: tags,
        isFavorite: _isFavorite,
        createdAt: widget.apiConfig?.createdAt,
      );

      if (widget.apiConfig != null) {
        await databaseService.updateApiConfig(api);
      } else {
        await databaseService.insertApiConfig(api);
      }

      await databaseService.close();

      if (mounted) {
        // 先返回 true，让列表页面刷新
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteApi() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${widget.apiConfig!.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final databaseService = DatabaseService();
        await databaseService.initialize();
        await databaseService.deleteApiConfig(widget.apiConfig!.id);
        await databaseService.close();

        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
