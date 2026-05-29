import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../providers/api_provider.dart';

class ApiFormScreen extends StatefulWidget {
  final ApiConfig? apiConfig;
  final bool isEditing;

  const ApiFormScreen({super.key, this.apiConfig, this.isEditing = false});

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
  bool _isValidating = false;
  bool _obscureApiKey = true;
  String _validationStatus = '';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '编辑API' : '添加API'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteApi,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
        maxWidth: 600,
        child: SingleChildScrollView(
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
                        if (value == null || value.trim().isEmpty) {
                          return '请输入API名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        labelText: 'API地址 *',
                        hintText: '例如：https://api.deepseek.com/v1',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.link),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.content_paste, size: 20),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (!mounted) return;
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              _baseUrlController.text = data.text!.trim();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已粘贴'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          tooltip: '粘贴',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入API地址';
                        }
                        final trimmed = value.trim();
                        if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
                          return '请输入有效的URL';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      decoration: InputDecoration(
                        labelText: 'API Key *',
                        hintText: '输入你的API密钥',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureApiKey = !_obscureApiKey;
                                });
                              },
                              tooltip: _obscureApiKey ? '显示' : '隐藏',
                            ),
                            IconButton(
                              icon: const Icon(Icons.content_paste, size: 20),
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null && data!.text!.isNotEmpty) {
                                  _apiKeyController.text = data.text!.trim();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已粘贴'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                              tooltip: '粘贴',
                            ),
                          ],
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入API Key';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _modelsController,
                      decoration: InputDecoration(
                        labelText: '模型列表',
                        hintText: '用逗号分隔，或点击获取',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.smart_toy),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: _isFetchingModels
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.download, size: 20),
                              onPressed: _isFetchingModels ? null : _fetchModels,
                              tooltip: '获取可用模型',
                            ),
                          ],
                        ),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    if (_validationStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _validationStatus,
                          style: TextStyle(
                            color: _validationStatus.contains('成功') || _validationStatus.contains('有效')
                                ? AppColors.success
                                : AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isValidating ? null : _validateApi,
                            icon: _isValidating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: const Text('验证API'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isFetchingModels ? null : _fetchModels,
                            icon: const Icon(Icons.refresh),
                            label: const Text('获取模型'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 分组：支持输入和选择已有分组
                    Consumer<ApiProvider>(
                      builder: (context, provider, _) {
                        final groups = provider.availableGroups;
                        return DropdownButtonFormField<String>(
                          initialValue: groups.contains(_groupController.text) ? _groupController.text : null,
                          decoration: InputDecoration(
                            labelText: '分组',
                            hintText: '选择或输入新分组',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.folder),
                            suffixIcon: groups.isNotEmpty
                                ? null
                                : null,
                          ),
                          items: [
                            ...groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _groupController.text = value;
                            }
                          },
                        );
                      },
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
                    DropdownButtonFormField<String>(
                      initialValue: _environment,
                      decoration: const InputDecoration(
                        labelText: '环境',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.cloud),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'development', child: Text('开发')),
                        DropdownMenuItem(value: 'staging', child: Text('测试')),
                        DropdownMenuItem(value: 'production', child: Text('生产')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _environment = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('收藏'),
                      subtitle: const Text('添加到收藏列表'),
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
                    ElevatedButton(
                      onPressed: _saveApi,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(widget.isEditing ? '保存修改' : '添加API'),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _validateApi() async {
    if (_baseUrlController.text.trim().isEmpty || _apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写 API 地址和 API Key'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _validationStatus = '';
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

      final result = await apiService.validateApi(apiConfig);

      if (mounted) {
        setState(() {
          _isValidating = false;
          _validationStatus = result['message'] as String? ?? '验证完成';

          if (result['valid'] == true && result['models'] != null) {
            final models = result['models'] as List<String>;
            if (models.isNotEmpty) {
              _modelsController.text = models.join(', ');
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isValidating = false;
          _validationStatus = '验证失败: $e';
        });
      }
    }
  }

  Future<void> _fetchModels() async {
    if (_baseUrlController.text.trim().isEmpty || _apiKeyController.text.trim().isEmpty) {
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
      final provider = context.read<ApiProvider>();

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
        id: widget.isEditing ? widget.apiConfig!.id : const Uuid().v4(),
        name: _nameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: models,
        environment: _environment,
        group: _groupController.text.trim().isNotEmpty ? _groupController.text.trim() : null,
        tags: tags,
        isFavorite: _isFavorite,
        createdAt: widget.isEditing ? widget.apiConfig!.createdAt : null,
      );

      // 重复检测
      if (!widget.isEditing) {
        final duplicate = provider.apiConfigs.where((c) =>
          c.baseUrl.trim() == api.baseUrl.trim() && c.apiKey.trim() == api.apiKey.trim()
        ).toList();
        if (duplicate.isNotEmpty) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('检测到重复'),
              content: Text('已存在相同地址和Key的配置：${duplicate.first.name}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('仍然添加')),
              ],
            ),
          );
          if (proceed != true) {
            setState(() { _isLoading = false; });
            return;
          }
        }
      }

      if (widget.isEditing) {
        await provider.updateApiConfig(api);
      } else {
        await provider.addApiConfig(api);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? 'API已更新' : 'API已添加'),
            backgroundColor: AppColors.success,
          ),
        );
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
        final provider = context.read<ApiProvider>();
        await provider.deleteApiConfig(widget.apiConfig!.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已删除 ${widget.apiConfig!.name}'),
              backgroundColor: AppColors.success,
            ),
          );
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
