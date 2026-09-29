import 'dart:convert';

String? extractSyncIp(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final jsonIp = _extractFromJson(trimmed);
  if (jsonIp != null) return jsonIp;

  final firstField = trimmed.split('|').first.trim();
  final uri = Uri.tryParse(firstField);
  final candidate = _candidateFromUri(uri) ?? firstField;
  return _isValidIPv4(candidate) ? candidate : null;
}

/// 从二维码内容中提取可选的同步加密密钥（`k=<base64url>` 段）。
/// 旧版二维码没有该段，返回 null，走明文+确认流程。
String? extractSyncKey(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.startsWith('{')) return null;
  for (final segment in trimmed.split('|')) {
    final part = segment.trim();
    if (part.startsWith('k=') && part.length > 2) {
      return part.substring(2);
    }
  }
  return null;
}

String? _extractFromJson(String value) {
  if (!value.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) return null;

    final direct = decoded['ip'] ?? decoded['ipAddress'] ?? decoded['host'];
    if (direct is String && _isValidIPv4(direct.trim())) {
      return direct.trim();
    }

    final device = decoded['device'];
    if (device is Map<String, dynamic>) {
      final nested = device['ipAddress'] ?? device['ip'];
      if (nested is String && _isValidIPv4(nested.trim())) {
        return nested.trim();
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _candidateFromUri(Uri? uri) {
  if (uri == null || !uri.hasScheme) return null;
  final queryIp = uri.queryParameters['ip'] ?? uri.queryParameters['host'];
  if (queryIp != null && queryIp.isNotEmpty) return queryIp.trim();
  if (uri.host.isNotEmpty) return uri.host.trim();
  return null;
}

bool _isValidIPv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    // 只接受纯数字段，拒绝 "+4"、空格等 int.tryParse 会放行的写法。
    if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return false;
    final number = int.parse(part);
    if (number < 0 || number > 255) return false;
  }
  return true;
}
