import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';

class RequestForm extends StatefulWidget {
  final ApiConfig apiConfig;
  final Function(String model, String endpoint, Map<String, dynamic> body) onSubmit;

  const RequestForm({
    super.key,
    required this.apiConfig,
    required this.onSubmit,
  });

  @override
  State<RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
  String? _selectedModel;
  final _endpointController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.apiConfig.models.isNotEmpty) {
      _selectedModel = widget.apiConfig.models.first;
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
              value: _selectedModel,
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
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('发送请求'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
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
