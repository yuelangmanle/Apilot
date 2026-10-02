import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/api_profile.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../providers/api_provider.dart';
import '../../../core/services/ai/ai_service.dart';
import '../services/api_connection_paste_parser.dart';

class ApiFormScreen extends StatefulWidget {
  final ApiConfig? apiConfig;
  final bool isEditing;

  /// FAB"从剪贴板识别"路径携带的预填结果。
  final ApiConnectionPasteResult? initialConnection;

  /// 扫码导入路径携带的名称预填。
  final String? initialName;

  const ApiFormScreen({
    super.key,
    this.apiConfig,
    this.isEditing = false,
    this.initialConnection,
    this.initialName,
  });

  @override
  State<ApiFormScreen> createState() => _ApiFormScreenState();
}

class _ApiFormScreenState extends State<ApiFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelsController = TextEditingController();
  final _tagsController = TextEditingController();
  String? _selectedGroup;
  String _environment = 'development';
  bool _isFavorite = false;
  DateTime? _expiresAt;
  final _lowBalanceController = TextEditingController();
  final _monthlyBudgetController = TextEditingController();
  final _extraKeysController = TextEditingController();
  bool _isLoading = false;
  bool _isFetchingModels = false;
  bool _isValidating = false;
  bool _obscureApiKey = true;
  String _validationStatus = '';
  bool _saved = false;
  ApiConnectionPasteResult? _clipboardSuggestion;
  late final Map<String, String> _initialTextValues;
  late final String? _initialGroup;
  late final String _initialEnvironment;
  late final bool _initialFavorite;

  @override
  void initState() {
    super.initState();
    if (widget.apiConfig != null) {
      final api = widget.apiConfig!;
      _nameController.text = api.name;
      _baseUrlController.text = api.baseUrl;
      _apiKeyController.text = api.apiKey;
      _modelsController.text = api.models.join(', ');
      _selectedGroup = api.group;
      _tagsController.text = api.tags.join(', ');
      _environment = api.environment;
      _isFavorite = api.isFavorite;
    }
    if (widget.initialName != null && widget.apiConfig == null) {
      _nameController.text = widget.initialName!;
    }
    // 预填在快照之后：预填内容算作"未保存修改"，返回时有保护。
    if (widget.initialConnection != null && widget.apiConfig == null) {
      _baseUrlController.text = widget.initialConnection!.baseUrl;
      _apiKeyController.text = widget.initialConnection!.apiKey;
    }
    _initialTextValues = {
      'name': _nameController.text,
      'baseUrl': _baseUrlController.text,
      'apiKey': _apiKeyController.text,
      'models': _modelsController.text,
      'tags': _tagsController.text,
    };
    _initialGroup = _selectedGroup;
    _initialEnvironment = _environment;
    _initialFavorite = _isFavorite;
    _probeClipboard();
  }

  /// 激活优化：进入表单时自动探测剪贴板，识别到成对的地址+Key 就
  /// 给出一键填入的横幅（不自动覆盖表单，由用户确认）。
  Future<void> _probeClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty || !mounted) return;
      final parsed = ApiConnectionPasteParser.parse(text);
      if (parsed == null || !mounted) return;
      final alreadyFilled = _baseUrlController.text.trim() == parsed.baseUrl &&
          _apiKeyController.text.trim() == parsed.apiKey;
      if (alreadyFilled) return;
      setState(() => _clipboardSuggestion = parsed);
    } catch (_) {
      // 剪贴板不可读不影响表单使用。
    }
  }

  /// 备用 Key 池：一行一把，写入 metadata.extraKeys（KeyPool 故障转移读取）。
  Map<String, dynamic>? _mergeExtraKeys(Map<String, dynamic>? original) {
    final lines = _extraKeysController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final merged = Map<String, dynamic>.from(original ?? <String, dynamic>{});
    if (lines.isEmpty) {
      merged.remove('extraKeys');
    } else {
      merged['extraKeys'] = lines;
    }
    return merged.isEmpty ? null : merged;
  }

  /// 就地新建分组：免去"放弃表单 → 设置 → 建组 → 重填"的断点。
  Future<void> _createGroupInline(ApiProvider provider) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '分组名称', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await provider.createGroup(name);
      if (!mounted) return;
      setState(() => _selectedGroup = created);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('StateError: ', '')),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  bool _hasUnsavedChanges() {
    if (_initialTextValues['name'] != _nameController.text ||
        _initialTextValues['baseUrl'] != _baseUrlController.text ||
        _initialTextValues['apiKey'] != _apiKeyController.text ||
        _initialTextValues['models'] != _modelsController.text ||
        _initialTextValues['tags'] != _tagsController.text) {
      return true;
    }
    return _selectedGroup != _initialGroup ||
        _environment != _initialEnvironment ||
        _isFavorite != _initialFavorite;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _extraKeysController.dispose();
    _lowBalanceController.dispose();
    _monthlyBudgetController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelsController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_saved || !_hasUnsavedChanges()) {
          navigator.pop(_saved);
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('放弃未保存的修改？'),
            content: const Text('表单内容尚未保存，返回后将丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('放弃修改',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          navigator.pop(false);
        }
      },
      child: Scaffold(
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
                      if (_clipboardSuggestion != null)
                        Card(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.auto_fix_high,
                                color: AppColors.primary),
                            title: const Text('检测到剪贴板中的连接信息',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(_clipboardSuggestion!.baseUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11)),
                            trailing: TextButton(
                              onPressed: () {
                                setState(() {
                                  _baseUrlController.text =
                                      _clipboardSuggestion!.baseUrl;
                                  _apiKeyController.text =
                                      _clipboardSuggestion!.apiKey;
                                  _clipboardSuggestion = null;
                                });
                              },
                              child: const Text('一键填入'),
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _recognizePastedConnection,
                        icon: const Icon(Icons.content_paste_search),
                        label: const Text('粘贴识别地址和 Key'),
                      ),
                      const SizedBox(height: 16),
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
                              final messenger = ScaffoldMessenger.of(context);
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (!mounted) return;
                              if (data?.text != null &&
                                  data!.text!.isNotEmpty) {
                                _baseUrlController.text = data.text!.trim();
                                messenger.showSnackBar(
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
                          if (!trimmed.startsWith('http://') &&
                              !trimmed.startsWith('https://')) {
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
                                  _obscureApiKey
                                      ? Icons.visibility_off
                                      : Icons.visibility,
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
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final data = await Clipboard.getData(
                                      Clipboard.kTextPlain);
                                  if (!mounted) return;
                                  if (data?.text != null &&
                                      data!.text!.isNotEmpty) {
                                    _apiKeyController.text = data.text!.trim();
                                    messenger.showSnackBar(
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
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download, size: 20),
                                onPressed:
                                    _isFetchingModels ? null : _fetchModels,
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
                              color: _validationStatus.contains('成功') ||
                                      _validationStatus.contains('有效')
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
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: const Text('验证API'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isFetchingModels ? null : _fetchModels,
                              icon: const Icon(Icons.refresh),
                              label: const Text('获取模型'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 分组由设置页统一管理，避免出现无法筛选的自由文本分组。
                      Consumer<ApiProvider>(
                        builder: (context, provider, _) {
                          final groups = provider.managedGroupNames;
                          return DropdownButtonFormField<String?>(
                            initialValue: groups.contains(_selectedGroup)
                                ? _selectedGroup
                                : null,
                            decoration: const InputDecoration(
                              labelText: '分组',
                              hintText: '选择分组或就地新建',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.folder),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('未分组'),
                              ),
                              ...groups.map(
                                (group) => DropdownMenuItem<String?>(
                                  value: group,
                                  child: Text(group),
                                ),
                              ),
                              const DropdownMenuItem<String?>(
                                value: '__create_new__',
                                child: Text('＋ 新建分组…'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == '__create_new__') {
                                await _createGroupInline(provider);
                                return;
                              }
                              setState(() => _selectedGroup = value);
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
                          DropdownMenuItem(
                              value: 'development', child: Text('开发')),
                          DropdownMenuItem(value: 'staging', child: Text('测试')),
                          DropdownMenuItem(
                              value: 'production', child: Text('生产')),
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('生命周期（可选）',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              const SizedBox(height: 8),
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.event_outlined,
                                    size: 20),
                                title: Text(_expiresAt == null
                                    ? 'Key 到期日'
                                    : '到期日：${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}'),
                                trailing: _expiresAt == null
                                    ? const Icon(Icons.chevron_right)
                                    : IconButton(
                                        icon: const Icon(Icons.close,
                                            size: 18),
                                        onPressed: () =>
                                            setState(() => _expiresAt = null),
                                      ),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _expiresAt ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate:
                                        DateTime.now().add(const Duration(days: 3650)),
                                  );
                                  if (picked != null) {
                                    setState(() => _expiresAt = picked);
                                  }
                                },
                              ),
                              TextField(
                                controller: _lowBalanceController,
                                keyboardType: TextInputType.text,
                                decoration: const InputDecoration(
                                  labelText: '余额低水位线（如 10）',
                                  hintText: '低于该值时体检提醒',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _monthlyBudgetController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: '每月预算上限（USD，可选）',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _extraKeysController,
                                minLines: 2,
                                maxLines: 5,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: '备用 Key 池（可选）',
                                  hintText: '每行一把 Key；主 Key 失效时自动切换',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
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
      ),
    );
  }

  /// 解析 AI 返回的 JSON（容错：允许包裹在 ```json 里或带前后缀文本）。
  ApiConnectionPasteResult? _parseAiConnectionJson(String? answer) {
    if (answer == null) return null;
    var text = answer.trim();
    final fence = RegExp(r'```(?:json)?').allMatches(text);
    if (fence.isNotEmpty) {
      text = text.replaceAll(RegExp(r'```(?:json)?'), '').trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map) return null;
      final baseUrl = (decoded['baseUrl'] as String? ?? '').trim();
      final apiKey = (decoded['apiKey'] as String? ?? '').trim();
      if (baseUrl.isEmpty || apiKey.isEmpty) return null;
      final models = (decoded['models'] as List?)
              ?.whereType<String>()
              .where((m) => m.trim().isNotEmpty)
              .map((m) => m.trim())
              .toList() ??
          const [];
      return ApiConnectionPasteResult(
        baseUrl: baseUrl,
        apiKey: apiKey,
        urlWasNormalized: false,
        models: models,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _recognizePastedConnection() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final textController = TextEditingController(text: clipboard?.text ?? '');
    ApiConnectionPasteResult? parsed;
    String? error;
    bool aiParsing = false;

    final result = await showDialog<ApiConnectionPasteResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('识别 API 连接信息'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textController,
                  autofocus: textController.text.isEmpty,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '粘贴包含地址和 Key 的文本',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (aiParsing)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI 识别'),
                onPressed: () async {
                  final raw = textController.text.trim();
                  if (raw.isEmpty) return;
                  setDialogState(() {
                    aiParsing = true;
                    error = null;
                  });
                  final configs =
                      context.read<ApiProvider>().allApiConfigs;
                  final answer = await AiService.ask(
                    systemPrompt: '你是 API 配置解析器。从用户给的文本里提取 API 信息，'
                        '只输出一行 JSON：{"baseUrl":"...","apiKey":"...",'
                        '"models":["..."]}。找不到的字段给空字符串或空数组。'
                        'baseUrl 必须是 http(s) 开头的完整地址。不要输出任何解释。',
                    userPrompt: raw.length > 4000
                        ? raw.substring(0, 4000)
                        : raw,
                    configs: configs,
                    maxTokens: 300,
                  );
                  if (!dialogContext.mounted) return;
                  final candidate = _parseAiConnectionJson(answer);
                  setDialogState(() {
                    aiParsing = false;
                    if (candidate == null) {
                      error = answer == null
                          ? 'AI 未配置或调用失败，请先在「设置 → AI 助手」里配置来源'
                          : 'AI 没能从这段文本里提取出地址和 Key';
                    }
                  });
                  if (candidate != null) {
                    Navigator.pop(dialogContext, candidate);
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () {
                final candidate =
                    ApiConnectionPasteParser.parse(textController.text);
                if (candidate == null) {
                  setDialogState(() {
                    error = '未同时识别到有效的 API 地址和 Key';
                  });
                  return;
                }
                parsed = candidate;
                Navigator.pop(dialogContext, candidate);
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('识别并填入'),
            ),
          ],
        ),
      ),
    );
    textController.dispose();
    if (!mounted || result == null || parsed == null) return;

    setState(() {
      _baseUrlController.text = result.baseUrl;
      _apiKeyController.text = result.apiKey;
      if (result.models.isNotEmpty &&
          _modelsController.text.trim().isEmpty) {
        _modelsController.text = result.models.join(', ');
      }
      _validationStatus = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.urlWasNormalized
              ? '已识别并修正 API 地址格式，请继续填写名称、模型和分组'
              : '已识别 API 地址和 Key，请继续填写名称、模型和分组',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _validateApi() async {
    if (_baseUrlController.text.trim().isEmpty ||
        _apiKeyController.text.trim().isEmpty) {
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
          _validationStatus = friendlyError(e);
        });
      }
    }
  }

  Future<void> _fetchModels() async {
    if (_baseUrlController.text.trim().isEmpty ||
        _apiKeyController.text.trim().isEmpty) {
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
            content: Text(friendlyError(e)),
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

      // 编辑与模板创建都要保留表单之外的字段（selectedModel/providerId/
      // metadata/导入溯源等）：否则编辑一次就抹掉模型目录，从模板添加
      // 则会把 anthropic_messages 等协议标识丢回 custom。
      final original = widget.apiConfig;
      final api = ApiConfig(
        id: widget.isEditing ? original!.id : const Uuid().v4(),
        name: _nameController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: models,
        environment: _environment,
        group: _selectedGroup,
        tags: tags,
        isFavorite: _isFavorite,
        createdAt: widget.isEditing ? original!.createdAt : null,
        metadata: _mergeExtraKeys(original?.metadata),
        providerId: original?.providerId ?? ApiProviderIds.custom,
        protocolId: original?.protocolId ?? ApiProtocolIds.openAiCompatible,
        selectedModel: original?.selectedModel,
        modelCatalogMode: original?.modelCatalogMode ?? ApiModelCatalogModes.saved,
        modelSource: original?.modelSource ?? ApiModelSources.manual,
        modelsRefreshedAt: original?.modelsRefreshedAt,
        importSourceName: original?.importSourceName,
        importSourcePackage: original?.importSourcePackage,
        importTrustLevel: original?.importTrustLevel,
        expiresAt: _expiresAt,
        lowBalanceThreshold: _lowBalanceController.text.trim().isEmpty
            ? null
            : _lowBalanceController.text.trim(),
        monthlyBudget: double.tryParse(
            _monthlyBudgetController.text.trim()),
      );

      // 重复检测（基于全量配置，不受当前搜索/筛选影响）
      if (!widget.isEditing) {
        final duplicate = provider.allApiConfigs
            .where((c) =>
                c.baseUrl.trim() == api.baseUrl.trim() &&
                c.apiKey.trim() == api.apiKey.trim())
            .toList();
        if (duplicate.isNotEmpty) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('检测到重复'),
              content: Text('已存在相同地址和Key的配置：${duplicate.first.name}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('仍然添加')),
              ],
            ),
          );
          if (proceed != true) {
            setState(() {
              _isLoading = false;
            });
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
        _saved = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? 'API已更新' : 'API已添加'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
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
        title: const Text('移入回收站？'),
        content: Text('「${widget.apiConfig!.name}」将移入回收站，保留期内可随时恢复。'),
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
        if (!mounted) return;
        final provider = context.read<ApiProvider>();
        await provider.deleteApiConfig(widget.apiConfig!.id);

        if (mounted) {
          _saved = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已移入回收站：${widget.apiConfig!.name}'),
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
              content: Text(friendlyError(e)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
