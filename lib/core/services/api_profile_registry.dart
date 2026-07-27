import '../models/api_profile.dart';

class ApiProfileRegistry {
  const ApiProfileRegistry._();

  static ApiProfile resolve({
    required String baseUrl,
    String? providerId,
    String? protocolId,
  }) {
    final normalizedProviderId = _normalizeProviderId(providerId);
    final inferredProviderId = normalizedProviderId ?? _inferProvider(baseUrl);
    final resolvedProviderId = inferredProviderId ?? ApiProviderIds.custom;
    final resolvedProtocolId = _normalizeProtocolId(protocolId) ??
        _defaultProtocolFor(resolvedProviderId);

    return ApiProfile(
      providerId: resolvedProviderId,
      protocolId: resolvedProtocolId,
      providerDisplayName: _providerDisplayName(resolvedProviderId),
      protocolDisplayName: _protocolDisplayName(resolvedProtocolId),
    );
  }

  static String _defaultProtocolFor(String providerId) {
    switch (providerId) {
      case ApiProviderIds.anthropic:
        return ApiProtocolIds.anthropicMessages;
      case ApiProviderIds.google:
        return ApiProtocolIds.googleGenAi;
      default:
        return ApiProtocolIds.openAiCompatible;
    }
  }

  static String? _inferProvider(String baseUrl) {
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
    if (host == 'api.deepseek.com' || host.endsWith('.deepseek.com')) {
      return ApiProviderIds.deepseek;
    }
    if (host == 'api.openai.com' || host.endsWith('.openai.com')) {
      return ApiProviderIds.openai;
    }
    if (host == 'api.anthropic.com' || host.endsWith('.anthropic.com')) {
      return ApiProviderIds.anthropic;
    }
    if (host == 'generativelanguage.googleapis.com' ||
        host.endsWith('.googleapis.com')) {
      return ApiProviderIds.google;
    }
    return null;
  }

  static String _providerDisplayName(String providerId) {
    switch (providerId) {
      case ApiProviderIds.deepseek:
        return 'DeepSeek';
      case ApiProviderIds.openai:
        return 'OpenAI';
      case ApiProviderIds.anthropic:
        return 'Anthropic';
      case ApiProviderIds.google:
        return 'Google AI';
      default:
        return '自定义服务';
    }
  }

  static String _protocolDisplayName(String protocolId) {
    switch (protocolId) {
      case ApiProtocolIds.anthropicMessages:
        return 'Anthropic Messages';
      case ApiProtocolIds.googleGenAi:
        return 'Google GenAI';
      default:
        return 'OpenAI 兼容';
    }
  }

  static String? _normalizeProviderId(String? value) {
    final normalized = _normalize(value);
    if (normalized == null) return null;
    const providerIds = <String>{
      ApiProviderIds.deepseek,
      ApiProviderIds.openai,
      ApiProviderIds.anthropic,
      ApiProviderIds.google,
      ApiProviderIds.custom,
    };
    return providerIds.contains(normalized) ? normalized : null;
  }

  static String? _normalizeProtocolId(String? value) {
    final normalized = _normalize(value);
    if (normalized == null) return null;
    const protocolIds = <String>{
      ApiProtocolIds.openAiCompatible,
      ApiProtocolIds.anthropicMessages,
      ApiProtocolIds.googleGenAi,
    };
    return protocolIds.contains(normalized) ? normalized : null;
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
