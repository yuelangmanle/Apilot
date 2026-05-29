import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/models/api_config.dart';
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
    _endpointController.text = '/v1/chat/completions';
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
              },
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _endpointController,
            decoration: const InputDecoration(
              labelText: '端点',
              border: OutlineInputBorder(),
            ),
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
          ElevatedButton(
            onPressed: () {
              if (_selectedModel == null || _selectedModel!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('请选择或输入模型'),
                    backgroundColor: AppColors.warning,
                  ),
                );
                return;
              }

              Map<String, dynamic> body = {};
              try {
                body = jsonDecode(_bodyController.text) as Map<String, dynamic>;
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('JSON格式错误: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              widget.onSubmit(
                _selectedModel!,
                _endpointController.text,
                body,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('发送请求'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}
