import '../models/api_config.dart';

/// 安全仪表盘检查项：全部基于本地数据计算，无网络请求。
enum SecurityFindingLevel { warning, info }

class SecurityFinding {
  final SecurityFindingLevel level;
  final String title;
  final String detail;
  final List<String> configIds;

  const SecurityFinding({
    required this.level,
    required this.title,
    required this.detail,
    this.configIds = const [],
  });
}

class SecurityAudit {
  const SecurityAudit._();

  /// 审计全部存活配置，返回发现列表（无发现 = 安全状态良好）。
  static List<SecurityFinding> audit({
    required List<ApiConfig> configs,
    required bool appLockEnabled,
  }) {
    final findings = <SecurityFinding>[];

    // 1. http:// 明文端点（本地/回环地址豁免）。
    final plainHttp = configs.where((c) {
      final url = c.baseUrl.toLowerCase();
      if (!url.startsWith('http://')) return false;
      final host = Uri.tryParse(c.baseUrl)?.host ?? '';
      return host != 'localhost' &&
          host != '127.0.0.1' &&
          !host.startsWith('192.168.') &&
          !host.startsWith('10.');
    }).toList();
    if (plainHttp.isNotEmpty) {
      findings.add(SecurityFinding(
        level: SecurityFindingLevel.warning,
        title: '明文 HTTP 端点',
        detail:
            '以下配置使用 http:// 明文传输，API Key 在网络上可见（本机/局域网地址除外）：',
        configIds: plainHttp.map((c) => c.id).toList(),
      ));
    }

    // 2. 同一把 Key 用于多个配置。
    final byKey = <String, List<ApiConfig>>{};
    for (final config in configs) {
      if (config.apiKey.isEmpty) continue;
      byKey.putIfAbsent(config.apiKey, () => []).add(config);
    }
    final reused = byKey.values.where((list) => list.length > 1);
    if (reused.isNotEmpty) {
      findings.add(SecurityFinding(
        level: SecurityFindingLevel.info,
        title: '同一把 Key 复用于多个配置',
        detail:
            '共 ${reused.length} 把 Key 被多个配置共用。一处泄露会同时影响这些配置，建议为每个用途独立签发 Key：',
        configIds: [
          for (final list in reused) ...list.map((c) => c.id)
        ],
      ));
    }

    // 3. 未配置任何加密保护提示。
    if (!appLockEnabled) {
      findings.add(const SecurityFinding(
        level: SecurityFindingLevel.info,
        title: '应用锁未开启',
        detail: '密钥库已加密存储，但解锁手机即可查看。开启应用锁（PIN/指纹）可多加一道防线。',
      ));
    }

    return findings;
  }
}
