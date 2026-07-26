import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/theme/color_scheme.dart';
import '../../api_management/providers/api_provider.dart';
import '../models/third_party_import_models.dart';

class ThirdPartyImportConfirmScreen extends StatefulWidget {
  final ThirdPartyImportPayload payload;

  const ThirdPartyImportConfirmScreen({
    super.key,
    required this.payload,
  });

  @override
  State<ThirdPartyImportConfirmScreen> createState() =>
      _ThirdPartyImportConfirmScreenState();
}

class _ThirdPartyImportConfirmScreenState
    extends State<ThirdPartyImportConfirmScreen> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ApiProvider>();
    final existingConfigs = provider.allApiConfigs;
    final sourceName = widget.payload.displaySourceName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认导入'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '将从 $sourceName 导入配置',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '确认后会生成新的配置 ID，不会覆盖现有配置。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ...widget.payload.configs.map(
            (candidate) => _ConfigPreviewCard(
              candidate: candidate,
              hasPotentialDuplicate: existingConfigs.any(
                candidate.isPotentialDuplicateOf,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isImporting ? null : () => Navigator.pop(context, false),
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isImporting || widget.payload.validConfigs.isEmpty
                      ? null
                      : _confirmImport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('确认导入'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmImport() async {
    setState(() {
      _isImporting = true;
    });

    final provider = context.read<ApiProvider>();
    final importedAt = DateTime.now();
    final formattedImportedAt =
        DateFormat('yyyy-MM-dd HH:mm').format(importedAt);
    final importNameSuffix = '（导入 $formattedImportedAt）';
    final importMetadata = <String, dynamic>{
      'importedFrom': 'third_party_android_intent',
      'sourceName': widget.payload.displaySourceName,
      'sourcePackage': widget.payload.displaySourcePackage,
      'requestId': widget.payload.request.requestId,
      'receivedAt': widget.payload.request.receivedAt.toIso8601String(),
    };

    var successCount = 0;
    final failureMessages = <String>[];

    for (final invalid in widget.payload.invalidConfigs) {
      final displayName = invalid.displayName;
      final reasons = invalid.errors.join('、');
      failureMessages.add(
        '$displayName：$reasons',
      );
    }

    for (final candidate in widget.payload.validConfigs) {
      try {
        final apiConfig = candidate.toApiConfig(
          id: const Uuid().v4(),
          importNameSuffix: importNameSuffix,
          importedAt: importedAt,
          importMetadata: importMetadata,
        );
        await provider.addApiConfig(apiConfig);
        successCount++;
      } catch (e) {
        final displayName = candidate.displayName;
        failureMessages.add('$displayName：$e');
      }
    }

    await provider.loadApiConfigs();

    if (!mounted) return;
    setState(() {
      _isImporting = false;
    });

    await _showImportResult(
      successCount: successCount,
      failureMessages: failureMessages,
    );

    if (!mounted) return;
    Navigator.pop(context, successCount > 0);
  }

  Future<void> _showImportResult({
    required int successCount,
    required List<String> failureMessages,
  }) async {
    final hasFailures = failureMessages.isNotEmpty;
    final failureCount = failureMessages.length;
    final hiddenFailureCount = failureCount - 5;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasFailures ? '导入完成，部分失败' : '导入完成'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('成功导入：$successCount 个'),
              if (hasFailures) ...[
                const SizedBox(height: 12),
                Text('失败：$failureCount 个'),
                const SizedBox(height: 8),
                ...failureMessages.take(5).map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          message,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                if (failureMessages.length > 5)
                  Text('还有 $hiddenFailureCount 条失败原因未显示'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _ConfigPreviewCard extends StatelessWidget {
  final ThirdPartyImportConfigCandidate candidate;
  final bool hasPotentialDuplicate;

  const _ConfigPreviewCard({
    required this.candidate,
    required this.hasPotentialDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final isValid = candidate.isValid;
    final modelCount = candidate.models.length;
    final errorSummary = candidate.errors.join('、');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isValid ? Icons.api : Icons.error_outline,
                  color: isValid ? AppColors.primary : AppColors.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    candidate.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _StatusChip(
                  label: candidate.containsApiKey ? '含 Key' : '无 Key',
                  color: candidate.containsApiKey
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PreviewLine(label: 'Base URL', value: candidate.baseUrl),
            _PreviewLine(
              label: '模型',
              value: candidate.models.isEmpty ? '未提供' : '$modelCount 个',
            ),
            _PreviewLine(label: '环境', value: candidate.environment),
            if (candidate.group != null)
              _PreviewLine(label: '分组', value: candidate.group!),
            if (candidate.tags.isNotEmpty)
              _PreviewLine(label: '标签', value: candidate.tags.join(', ')),
            if (hasPotentialDuplicate)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '检测到相似配置，将作为新配置导入。',
                  style: TextStyle(color: AppColors.warning),
                ),
              ),
            if (!isValid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '无法导入：$errorSummary',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '未提供' : value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
