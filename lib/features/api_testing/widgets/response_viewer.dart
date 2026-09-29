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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeBackground =
        isDark ? AppColors.darkSurface : AppColors.background;
    final codeBorder = isDark ? Colors.grey.shade700 : Colors.grey.shade300;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (response == null) {
      return Center(
        child: Text('发送请求查看响应',
            style: TextStyle(color: secondaryTextColor)),
      );
    }

    final statusCode = response!['statusCode'] as int?;
    final body = response!['body'];
    final duration = response!['duration'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (statusCode != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (statusCode >= 200 && statusCode < 300) ? AppColors.success : AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Status: $statusCode',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            if (duration != null) ...[
              const SizedBox(width: 16),
              Text(
                '耗时: ${duration}ms',
                style: TextStyle(color: secondaryTextColor, fontSize: 13),
              ),
            ],
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _formatJson(body)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                );
              },
              tooltip: '复制响应',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: codeBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: codeBorder),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _formatJson(body),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatJson(dynamic json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (_) {
      return json.toString();
    }
  }
}
