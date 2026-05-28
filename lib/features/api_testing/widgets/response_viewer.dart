import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../../shared/theme/color_scheme.dart';

class ResponseViewer extends StatelessWidget {
  final Map<String, dynamic>? response;
  final bool isLoading;

  const ResponseViewer({
    super.key,
    this.response,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (response == null) {
      return const Center(
        child: Text(
          '发送请求查看响应',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final statusCode = response!['statusCode'] as int;
    final body = response!['body'];
    final duration = response!['duration'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusCode == 200 ? AppColors.success : AppColors.error,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Status: $statusCode',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '耗时: ${duration}ms',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: body.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              child: Text(
                _formatJson(body),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatJson(dynamic json) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }
}
