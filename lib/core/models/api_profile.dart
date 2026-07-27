class ApiProfile {
  final String providerId;
  final String protocolId;
  final String providerDisplayName;
  final String protocolDisplayName;

  const ApiProfile({
    required this.providerId,
    required this.protocolId,
    required this.providerDisplayName,
    required this.protocolDisplayName,
  });
}

abstract final class ApiProviderIds {
  static const deepseek = 'deepseek';
  static const openai = 'openai';
  static const anthropic = 'anthropic';
  static const google = 'google';
  static const custom = 'custom';
}

abstract final class ApiProtocolIds {
  static const openAiCompatible = 'openai_compatible';
  static const anthropicMessages = 'anthropic_messages';
  static const googleGenAi = 'google_genai';
}

abstract final class ApiModelCatalogModes {
  static const saved = 'saved';
  static const remote = 'remote';
  static const none = 'none';
}

abstract final class ApiModelSources {
  static const manual = 'manual';
  static const refreshed = 'refreshed';
  static const thirdParty = 'third_party';
  static const unknown = 'unknown';
}

abstract final class ApiImportTrustLevels {
  static const signatureVerified = 'signature_verified';
  static const systemPackage = 'system_package';
  static const declared = 'declared';
  static const unknown = 'unknown';
}
