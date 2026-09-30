import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/security_audit.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';
import '../../security/app_lock_controller.dart';

/// 安全仪表盘：本地规则体检（明文端点/Key 复用/应用锁），无网络请求。
class SecurityDashboardScreen extends StatelessWidget {
  const SecurityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final appLockEnabled = context.watch<AppLockController>().enabled;
    final findings = SecurityAudit.audit(
      configs: configs,
      appLockEnabled: appLockEnabled,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final content = Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  findings.isEmpty
                      ? Icons.verified_user
                      : Icons.report_problem_outlined,
                  size: 36,
                  color: findings.isEmpty
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        findings.isEmpty ? '未发现问题' : '发现 ${findings.length} 项建议',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('全部为本地规则检查，不产生任何网络请求',
                          style: TextStyle(fontSize: 12, color: secondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: findings.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: findings.length,
                  itemBuilder: (context, index) {
                    final finding = findings[index];
                    final named = finding.configIds
                        .map((id) => configs
                            .where((c) => c.id == id)
                            .map((c) => c.name)
                            .toList())
                        .expand((names) => names)
                        .take(8);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  finding.level == SecurityFindingLevel.warning
                                      ? Icons.warning_amber_outlined
                                      : Icons.info_outline,
                                  size: 18,
                                  color: finding.level ==
                                          SecurityFindingLevel.warning
                                      ? AppColors.warning
                                      : AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(finding.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(finding.detail,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: secondary)),
                            if (named.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: named
                                    .map((name) => Chip(
                                          label: Text(name,
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('安全仪表盘')),
      body: isWide ? CenteredContent(maxWidth: 640, child: content) : content,
    );
  }
}

