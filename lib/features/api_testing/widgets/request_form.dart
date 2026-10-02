import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/ai/ai_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/prompt_preset_store.dart';
import '../../api_management/providers/api_provider.dart';
import '../../../shared/theme/color_scheme.dart';

class RequestForm extends StatefulWidget {
  final ApiConfig apiConfig;
  final Function(String model, String endpoint, Map<String, dynamic> body) onSubmit;
  final bool isLoading;
  final bool streamEnabled;
  final ValueChanged<bool>? onStreamChanged;
  final String? initialModel;
  final Map<String, dynamic>? initialBody;
  final bool streaming;
  final VoidCallback? onStop;

  const RequestForm({
    super.key,
    required this.apiConfig,
    required this.onSubmit,
    this.isLoading = false,
    this.streamEnabled = true,
    this.onStreamChanged,
    this.initialModel,
    this.initialBody,
    this.streaming = false,
    this.onStop,
  });

  @override
  State<RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
  String? _selectedModel;
  final _endpointController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _generatingBody = false;

  /// AI 生成请求体：用一句自然语言描述需求，生成合法 JSON 并填入编辑器。
  Future<void> _generateBodyWithAi() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final description = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI 生成请求体'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('用一句话描述你想发起的请求，AI 会生成对应的 JSON 请求体。',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '例如：问它北京今天天气怎么样，带上工具调用',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(dialogContext, text);
              },
              child: const Text('生成')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || description == null) return;

    setState(() => _generatingBody = true);
    final answer = await AiService.ask(
      systemPrompt: '你是 API 请求体生成器。根据用户描述输出一个合法的 JSON 对象，'
          '用于 OpenAI 兼容的 /chat/completions 请求（必须包含 model 和 messages）。'
          '只输出 JSON，不要 Markdown 代码围栏、不要解释。',
      userPrompt: '模型名：${_selectedModel ?? '未知'}\n'
          '当前请求体（可参考并修改）：${_bodyController.text}\n'
          '用户需求：$description',
      configs: context.read<ApiProvider>().allApiConfigs,
      maxTokens: 800,
    );
    if (!mounted) return;
    setState(() => _generatingBody = false);
    final formatted = _extractJsonBody(answer);
    if (formatted == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('AI 未配置或未能生成合法 JSON，请重试')));
      return;
    }
    setState(() => _bodyController.text = formatted);
    messenger.showSnackBar(const SnackBar(
        content: Text('已生成请求体，确认后发送'),
        backgroundColor: AppColors.success));
  }

  /// 从 AI 输出里提取 JSON 并格式化（容忍 ```json 围栏与前后说明文字）。
  String? _extractJsonBody(String? answer) {
    if (answer == null) return null;
    final text = answer.replaceAll(RegExp(r'```(?:json)?'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) return null;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _initFromApiConfig();
  }

  void _initFromApiConfig() {
    if (widget.initialModel != null &&
        widget.initialModel!.isNotEmpty &&
        (widget.apiConfig.models.isEmpty ||
            widget.apiConfig.models.contains(widget.initialModel))) {
      // 重测场景：优先用历史请求的模型。
      _selectedModel = widget.initialModel;
    } else if (widget.apiConfig.models.isNotEmpty) {
      _selectedModel = widget.apiConfig.models.first;
    } else {
      _selectedModel = null;
    }
    if (widget.initialBody != null && widget.initialBody!.isNotEmpty) {
      _endpointController.text = '/chat/completions';
      _bodyController.text =
          const JsonEncoder.withIndent('  ').convert(widget.initialBody);
      return;
    }
    // 智能设置默认端点：如果 base 已有 /v1，端点只写 /chat/completions
    final base = widget.apiConfig.baseUrl;
    if (base.contains('/v1') || base.contains('/v2') || base.contains('/v3')) {
      _endpointController.text = '/chat/completions';
    } else {
      _endpointController.text = '/v1/chat/completions';
    }
    _bodyController.text = '''
{
  "model": "${_selectedModel ?? ''}",
  "messages": [
    {
      "role": "user",
      "content": "Hello"
    }
  ],
  "temperature": 0.7
}''';
  }

  @override
  void didUpdateWidget(RequestForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiConfig.id != widget.apiConfig.id) {
      _initFromApiConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 预览拼接后的完整URL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请求URL预览', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  ApiService.buildUrl(widget.apiConfig.baseUrl, _endpointController.text),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (widget.apiConfig.models.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedModel,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
              ),
              items: widget.apiConfig.models.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedModel = value;
                  _updateBodyModel(value ?? '');
                });
              },
            )
          else
            TextFormField(
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: '输入模型名称',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _selectedModel = value;
                _updateBodyModel(value);
              },
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _endpointController,
            decoration: const InputDecoration(
              labelText: '端点',
              hintText: '/chat/completions',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}), // 刷新URL预览
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bodyController,
            decoration: const InputDecoration(
              labelText: '请求体 (JSON)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _savePreset,
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('存为预设', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showPresetPicker,
                icon: const Icon(Icons.bookmarks_outlined, size: 16),
                label: const Text('从预设填入', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _generatingBody ? null : _generateBodyWithAi,
                icon: _generatingBody
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_generatingBody ? '生成中…' : 'AI 生成请求体',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('流式输出', style: TextStyle(fontSize: 14)),
            subtitle:
                const Text('边生成边显示；服务不支持时可关闭', style: TextStyle(fontSize: 12)),
            value: widget.streamEnabled,
            onChanged: widget.onStreamChanged,
            secondary: const Icon(Icons.stream, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.isLoading ? null : _submit,
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label:
                      Text(widget.isLoading ? '请求中...' : '发送请求'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (widget.isLoading && widget.streaming && widget.onStop != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _updateBodyModel(String model) {
    try {
      final body = jsonDecode(_bodyController.text) as Map<String, dynamic>;
      body['model'] = model;
      _bodyController.text = const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {}
  }

  Future<void> _savePreset() async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(_bodyController.text) as Map<String, dynamic>;
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请求体不是有效 JSON，无法保存')),
      );
      return;
    }
    final controller = TextEditingController(
        text: _selectedModel == null || _selectedModel!.isEmpty
            ? '我的预设'
            : '预设 · $_selectedModel');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存为 Prompt 预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '预设名称', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await PromptPresetStore.save(PromptPreset(
      name: name,
      model: _selectedModel,
      body: body,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('已保存预设「$name」'),
          duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _showPresetPicker() async {
    final presets = await PromptPresetStore.loadAll();
    if (!mounted) return;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有预设，先点「存为预设」保存一个')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择预设',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final preset in presets)
              ListTile(
                title: Text(preset.name, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    preset.body['messages'] is List
                        ? '${(preset.body['messages'] as List).length} 条消息'
                        : '自定义请求体',
                    style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    await PromptPresetStore.delete(preset.name);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                onTap: () {
                  setState(() {
                    if (preset.model != null &&
                        preset.model!.isNotEmpty &&
                        (widget.apiConfig.models.isEmpty ||
                            widget.apiConfig.models
                                .contains(preset.model))) {
                      _selectedModel = preset.model;
                    }
                    _bodyController.text = const JsonEncoder.withIndent('  ')
                        .convert(preset.body);
                  });
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_selectedModel == null || _selectedModel!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或输入模型'), backgroundColor: AppColors.warning),
      );
      return;
    }

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(_bodyController.text) as Map<String, dynamic>;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON格式错误: $e'), backgroundColor: AppColors.error),
      );
      return;
    }

    widget.onSubmit(_selectedModel!, _endpointController.text, body);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
