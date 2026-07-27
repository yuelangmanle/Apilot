import '../models/api_config.dart';

class ApiConfigIdentity {
  const ApiConfigIdentity._();

  static bool matches(ApiConfig first, ApiConfig second) {
    return normalizeBaseUrl(first.baseUrl) == normalizeBaseUrl(second.baseUrl) &&
        first.apiKey == second.apiKey &&
        defaultModel(first) == defaultModel(second);
  }

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return trimmed.replaceFirst(RegExp(r'/+$'), '');
    }

    final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: normalizedPath,
        )
        .toString();
  }

  static String? defaultModel(ApiConfig config) {
    final selected = config.selectedModel?.trim();
    if (selected != null && selected.isNotEmpty) return selected;
    for (final model in config.models) {
      final normalized = model.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }
}
