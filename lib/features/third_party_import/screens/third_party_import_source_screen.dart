import 'package:flutter/material.dart';

import '../../../core/models/api_profile.dart';
import '../../../shared/theme/color_scheme.dart';
import '../models/third_party_import_models.dart';
import 'third_party_import_confirm_screen.dart';

class ThirdPartyImportSourceScreen extends StatelessWidget {
  final ThirdPartyImportRequest request;

  const ThirdPartyImportSourceScreen({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final payload = ThirdPartyImportPayload.parse(request);

    return Scaffold(
      appBar: AppBar(
        title: const Text('第三方导入'),
      ),
      body: payload.hasFatalError
          ? _FatalImportRequest(payload: payload)
          : _SourceReview(payload: payload),
    );
  }
}

class _FatalImportRequest extends StatelessWidget {
  final ThirdPartyImportPayload payload;

  const _FatalImportRequest({required this.payload});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        const SizedBox(height: 16),
        const Text(
          '无法读取导入请求',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          payload.fatalError ?? '导入请求无效',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _SourceReview extends StatelessWidget {
  final ThirdPartyImportPayload payload;

  const _SourceReview({required this.payload});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.security, color: AppColors.primary, size: 48),
        const SizedBox(height: 16),
        const Text(
          '第三方 App 请求导入 API 配置',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '请确认来源可信后再继续。Apilot 不会静默导入，也不会覆盖现有配置。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _InfoRow(label: '来源', value: payload.displaySourceName),
                _InfoRow(label: '包名', value: payload.displaySourcePackage),
                _InfoRow(
                  label: '可信度',
                  value: _trustLevelLabel(payload.trustLevel),
                  valueColor: _trustLevelColor(payload.trustLevel),
                ),
                if (payload.request.requestId != null)
                  _InfoRow(label: '请求 ID', value: payload.request.requestId!),
                if (payload.request.signatureSha256 != null)
                  _InfoRow(
                    label: '签名 SHA-256',
                    value: payload.request.signatureSha256!,
                    selectable: true,
                  ),
                _InfoRow(
                  label: '配置数量',
                  value: payload.configs.length.toString(),
                ),
                _InfoRow(
                  label: '有效配置',
                  value: payload.validConfigs.length.toString(),
                ),
                _InfoRow(
                  label: '包含密钥',
                  value: payload.containsSecrets ? '是' : '否',
                  valueColor: payload.containsSecrets
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.warning.withValues(alpha: 0.12),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '安全提示：第三方 App 可以提交配置，但只有你确认后才会写入。包含 API Key 的配置不会在页面完整展示。',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('导入规则：所有配置都会作为新配置保存，重复项不会覆盖原有配置。'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: payload.validConfigs.isEmpty
                    ? null
                    : () async {
                        final imported = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ThirdPartyImportConfirmScreen(
                              payload: payload,
                            ),
                          ),
                        );
                        if (!context.mounted) return;
                        if (imported == true) {
                          Navigator.pop(context, true);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('继续查看'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _trustLevelLabel(String trustLevel) {
    switch (trustLevel) {
      case ApiImportTrustLevels.signatureVerified:
        return '已验证包签名';
      case ApiImportTrustLevels.systemPackage:
        return '系统可见包名';
      case ApiImportTrustLevels.declared:
        return '调用方声明';
      default:
        return '未知';
    }
  }

  Color _trustLevelColor(String trustLevel) {
    switch (trustLevel) {
      case ApiImportTrustLevels.signatureVerified:
        return AppColors.success;
      case ApiImportTrustLevels.systemPackage:
        return AppColors.primary;
      case ApiImportTrustLevels.declared:
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool selectable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: valueColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value, style: textStyle)
                : Text(value, style: textStyle),
          ),
        ],
      ),
    );
  }
}
