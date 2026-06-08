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
    if (part.isEmpty) return false;
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return false;
  }
  return true;
}
