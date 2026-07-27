import 'dart:convert';

import '../../../core/models/api_config.dart';
import '../../../core/models/api_profile.dart';
import '../../../core/services/api_profile_registry.dart';

class ThirdPartyImportRequest {
  final bool openDocs;
  final String? payload;
  final String? error;
  final String? sourceName;
  final String? sourcePackage;
  final String? sourceAppName;
  final String? signatureSha256;
  final String? sourceIdentity;
  final String? declaredSignatureSha256;
  final String? requestId;
  final String? mimeType;
  final String? dataUri;
  final DateTime receivedAt;

  const ThirdPartyImportRequest({
    required this.openDocs,
    required this.payload,
    required this.error,
    required this.sourceName,
    required this.sourcePackage,
    required this.sourceAppName,
    required this.signatureSha256,
    this.sourceIdentity,
    this.declaredSignatureSha256,
    required this.requestId,
    required this.mimeType,
    required this.dataUri,
    required this.receivedAt,
  });

  factory ThirdPartyImportRequest.fromPlatformMap(Map<dynamic, dynamic> map) {
    final receivedAtMillis = _readInt(map['receivedAtMillis']);
    return ThirdPartyImportRequest(
      openDocs: map['openDocs'] == true,
      payload: _readString(map['payload']),
      error: _readString(map['error']),
      sourceName: _readString(map['sourceName']),
      sourcePackage: _readString(map['sourcePackage']),
      sourceAppName: _readString(map['sourceAppName']),
      signatureSha256: _readString(map['signatureSha256']),
      sourceIdentity: _readString(map['sourceIdentity']),
      declaredSignatureSha256: _readString(map['declaredSignatureSha256']),
      requestId: _readString(map['requestId']),
      mimeType: _readString(map['mimeType']),
      dataUri: _readString(map['dataUri']),
      receivedAt: receivedAtMillis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(receivedAtMillis),
    );
  }

  String get displaySourceName =>
      sourceAppName ?? sourceName ?? sourcePackage ?? '未知第三方 App';
}

enum ThirdPartyModelTransferMode {
  all('all'),
  defaultOnly('default_only');

  final String wireValue;

  const ThirdPartyModelTransferMode(this.wireValue);

  static ThirdPartyModelTransferMode fromWireValue(Object? value) {
    return value == defaultOnly.wireValue ? defaultOnly : all;
  }
}

enum ThirdPartyResultTransport {
  extra('extra'),
  contentUri('content_uri'),
  automatic('auto');

  final String wireValue;

  const ThirdPartyResultTransport(this.wireValue);

  static ThirdPartyResultTransport fromWireValue(Object? value) {
    for (final transport in values) {
      if (transport.wireValue == value) return transport;
    }
    return automatic;
  }
}

abstract final class ThirdPartyApiConfigScopes {
  static const connection = 'connection';
  static const modelsDefault = 'models.default';
  static const modelsAll = 'models.all';
  static const secretApiKey = 'secret.api_key';

  static const supported = <String>{
    connection,
    modelsDefault,
    modelsAll,
    secretApiKey,
  };

  static const defaultV2 = <String>{connection, modelsDefault};

  static List<String> sort(Set<String> scopes) {
    const order = <String>[
      connection,
      modelsDefault,
      modelsAll,
      secretApiKey,
    ];
    return order.where(scopes.contains).toList(growable: false);
  }

  static Set<String> normalize(Set<String> scopes) {
    final normalized = scopes.where(supported.contains).toSet();
    if (normalized.contains(modelsAll)) {
      normalized.add(modelsDefault);
    }
    return normalized;
  }
}

class ThirdPartyApiConfigPickRequest {
  final String? sourceName;
  final String? sourcePackage;
  final String? sourceAppName;
  final String? signatureSha256;
  final String? sourceIdentity;
  final String? declaredSignatureSha256;
  final String? requestId;
  final int schemaVersion;
  final ThirdPartyModelTransferMode modelMode;
  final Set<String> requestedScopes;
  final ThirdPartyResultTransport returnTransport;

  const ThirdPartyApiConfigPickRequest({
    required this.sourceName,
    required this.sourcePackage,
    required this.sourceAppName,
    required this.signatureSha256,
    this.sourceIdentity,
    this.declaredSignatureSha256,
    required this.requestId,
    required this.modelMode,
    this.schemaVersion = 1,
    this.requestedScopes = const <String>{},
    this.returnTransport = ThirdPartyResultTransport.extra,
  });

  const ThirdPartyApiConfigPickRequest.v2({
    required this.sourceName,
    required this.sourcePackage,
    required this.sourceAppName,
    required this.signatureSha256,
    this.sourceIdentity,
    this.declaredSignatureSha256,
    required this.requestId,
    this.requestedScopes = ThirdPartyApiConfigScopes.defaultV2,
    this.returnTransport = ThirdPartyResultTransport.automatic,
  })  : schemaVersion = 2,
        modelMode = ThirdPartyModelTransferMode.defaultOnly;

  factory ThirdPartyApiConfigPickRequest.fromPlatformMap(
    Map<dynamic, dynamic> map,
  ) {
    final schemaVersion = _readInt(map['schemaVersion']) == 2 ? 2 : 1;
    final requestedScopes = _readStringSet(map['requestedScopes'])
        .where(ThirdPartyApiConfigScopes.supported.contains)
        .toSet();
    if (schemaVersion == 2) {
      return ThirdPartyApiConfigPickRequest.v2(
        sourceName: _readString(map['sourceName']),
        sourcePackage: _readString(map['sourcePackage']),
        sourceAppName: _readString(map['sourceAppName']),
        signatureSha256: _readString(map['signatureSha256']),
        sourceIdentity: _readString(map['sourceIdentity']),
        declaredSignatureSha256: _readString(map['declaredSignatureSha256']),
        requestId: _readString(map['requestId']),
        requestedScopes: requestedScopes.isEmpty
            ? ThirdPartyApiConfigScopes.defaultV2
            : requestedScopes,
        returnTransport:
            ThirdPartyResultTransport.fromWireValue(map['returnTransport']),
      );
    }

    return ThirdPartyApiConfigPickRequest(
      sourceName: _readString(map['sourceName']),
      sourcePackage: _readString(map['sourcePackage']),
      sourceAppName: _readString(map['sourceAppName']),
      signatureSha256: _readString(map['signatureSha256']),
      sourceIdentity: _readString(map['sourceIdentity']),
      declaredSignatureSha256: _readString(map['declaredSignatureSha256']),
      requestId: _readString(map['requestId']),
      modelMode: ThirdPartyModelTransferMode.fromWireValue(map['modelMode']),
    );
  }

  bool get isV2 => schemaVersion == 2;

  String get displaySourceName =>
      sourceAppName ?? sourceName ?? sourcePackage ?? '未知第三方 App';

  String get trustLevel {
    if (sourceIdentity == ThirdPartySourceIdentity.callingPackage &&
        signatureSha256 != null &&
        declaredSignatureSha256 != null &&
        signatureSha256!.toUpperCase() ==
            declaredSignatureSha256!.toUpperCase()) {
      return ApiImportTrustLevels.signatureVerified;
    }
    if (sourceIdentity == ThirdPartySourceIdentity.callingPackage &&
        sourcePackage != null) {
      return ApiImportTrustLevels.systemPackage;
    }
    if (sourceName != null) return ApiImportTrustLevels.declared;
    return ApiImportTrustLevels.unknown;
  }
}

class ThirdPartyApiConfigPickPayload {
  final ApiConfig apiConfig;
  final ThirdPartyApiConfigPickRequest? request;
  final ThirdPartyModelTransferMode? modelMode;
  final Set<String> grantedScopes;

  const ThirdPartyApiConfigPickPayload._({
    required this.apiConfig,
    required this.request,
    required this.modelMode,
    required this.grantedScopes,
  });

  factory ThirdPartyApiConfigPickPayload.fromApiConfig(
    ApiConfig apiConfig, {
    ThirdPartyApiConfigPickRequest? request,
    ThirdPartyModelTransferMode? modelMode,
    Set<String>? grantedScopes,
  }) {
    assert(request != null || modelMode != null);
    return ThirdPartyApiConfigPickPayload._(
      apiConfig: apiConfig,
      request: request,
      modelMode: modelMode,
      grantedScopes: grantedScopes ??
          (request?.isV2 == true
              ? ThirdPartyApiConfigScopes.defaultV2
              : const <String>{}),
    );
  }

  String? get selectedModel =>
      apiConfig.selectedModel ??
      (apiConfig.models.isEmpty ? null : apiConfig.models.first);

  bool get isV2 => request?.isV2 == true;

  Map<String, dynamic> toJson() {
    if (isV2) return _toV2Json();
    return _toV1Json();
  }

  Map<String, dynamic> _toV1Json() {
    final legacyModelMode = modelMode ?? ThirdPartyModelTransferMode.all;
    final config = <String, dynamic>{
      'name': apiConfig.name,
      'baseUrl': apiConfig.baseUrl,
      'apiKey': apiConfig.apiKey,
      'environment': apiConfig.environment,
      if (apiConfig.group != null) 'group': apiConfig.group,
      if (apiConfig.tags.isNotEmpty) 'tags': apiConfig.tags,
      if (legacyModelMode == ThirdPartyModelTransferMode.all)
        'models': apiConfig.models,
    };

    return <String, dynamic>{
      'schemaVersion': 1,
      'modelMode': legacyModelMode.wireValue,
      'selectedModel': selectedModel,
      'apiConfig': config,
    };
  }

  Map<String, dynamic> _toV2Json() {
    final selectedRequest = request!;
    final allowedScopes = ThirdPartyApiConfigScopes.normalize(grantedScopes);
    final profile = ApiProfileRegistry.resolve(
      baseUrl: apiConfig.baseUrl,
      providerId: apiConfig.providerId,
      protocolId: apiConfig.protocolId,
    );
    final models = <String, dynamic>{
      if (allowedScopes.contains(ThirdPartyApiConfigScopes.modelsDefault))
        'selectedModel': selectedModel,
      'catalogMode': apiConfig.modelCatalogMode,
      'source': apiConfig.modelSource,
      if (apiConfig.modelsRefreshedAt != null)
        'refreshedAt': apiConfig.modelsRefreshedAt!.toIso8601String(),
      if (allowedScopes.contains(ThirdPartyApiConfigScopes.modelsAll))
        'availableModels': apiConfig.models,
    };

    return <String, dynamic>{
      'schemaVersion': 2,
      if (selectedRequest.requestId != null)
        'requestId': selectedRequest.requestId,
      'grantedScopes': ThirdPartyApiConfigScopes.sort(allowedScopes),
      'apiProfile': <String, dynamic>{
        if (allowedScopes.contains(ThirdPartyApiConfigScopes.connection))
          'connection': <String, dynamic>{
            'name': apiConfig.name,
            'baseUrl': apiConfig.baseUrl,
            'environment': apiConfig.environment,
            if (apiConfig.group != null) 'group': apiConfig.group,
            if (apiConfig.tags.isNotEmpty) 'tags': apiConfig.tags,
          },
        'provider': <String, dynamic>{
          'id': profile.providerId,
          'displayName': profile.providerDisplayName,
        },
        'protocol': <String, dynamic>{
          'id': profile.protocolId,
          'displayName': profile.protocolDisplayName,
        },
        'models': models,
        'secrets': <String, dynamic>{
          if (allowedScopes.contains(ThirdPartyApiConfigScopes.secretApiKey))
            'apiKey': apiConfig.apiKey,
        },
        'origin': <String, dynamic>{
          'appName': 'Apilot',
          'packageName': 'com.example.api_manager',
          'trustLevel': ApiImportTrustLevels.systemPackage,
        },
      },
    };
  }
}

class ThirdPartyImportPayload {
  final ThirdPartyImportRequest request;
  final int? schemaVersion;
  final String? sourceAppName;
  final String? sourcePackageName;
  final String? declaredSignatureSha256;
  final bool declaredContainsSecrets;
  final List<ThirdPartyImportConfigCandidate> configs;
  final String? fatalError;

  const ThirdPartyImportPayload({
    required this.request,
    required this.schemaVersion,
    required this.sourceAppName,
    required this.sourcePackageName,
    required this.declaredSignatureSha256,
    required this.declaredContainsSecrets,
    required this.configs,
    required this.fatalError,
  });

  factory ThirdPartyImportPayload.parse(ThirdPartyImportRequest request) {
    if (request.error != null && request.error!.trim().isNotEmpty) {
      return ThirdPartyImportPayload._fatal(request, request.error!);
    }

    final rawPayload = request.payload?.trim();
    if (rawPayload == null || rawPayload.isEmpty) {
      return ThirdPartyImportPayload._fatal(request, '无法读取导入请求：缺少 JSON 内容');
    }

    final decoded = _decodeJson(rawPayload);
    if (decoded is! Map<String, dynamic>) {
      return ThirdPartyImportPayload._fatal(request, '导入格式不是有效 JSON 对象');
    }

    final schemaVersion = _readInt(decoded['schemaVersion']);
    if (schemaVersion != 1 && schemaVersion != 2) {
      return ThirdPartyImportPayload._fatal(request, '导入格式版本不支持');
    }
    final supportedSchemaVersion = schemaVersion!;

    final source = _readMap(decoded['source']);
    final options = _readMap(decoded['options']);
    final rawConfigs =
        decoded[supportedSchemaVersion == 2 ? 'apiProfiles' : 'apiConfigs'];
    if (rawConfigs is! List) {
      final listName =
          supportedSchemaVersion == 2 ? 'apiProfiles' : 'apiConfigs';
      return ThirdPartyImportPayload._fatal(request, '导入格式缺少 $listName 列表');
    }
    if (rawConfigs.isEmpty) {
      return ThirdPartyImportPayload._fatal(request, '没有可导入的 API 配置');
    }

    final configs = <ThirdPartyImportConfigCandidate>[];
    for (var i = 0; i < rawConfigs.length; i++) {
      configs.add(
        ThirdPartyImportConfigCandidate.fromJson(
          rawConfigs[i],
          i,
          schemaVersion: supportedSchemaVersion,
        ),
      );
    }

    final containsSecrets = options['containsSecrets'] == true ||
        configs.any((config) => config.containsApiKey);
    return ThirdPartyImportPayload(
      request: request,
      schemaVersion: supportedSchemaVersion,
      sourceAppName: _readString(source['appName']),
      sourcePackageName: _readString(source['packageName']),
      declaredSignatureSha256: _readString(source['signatureSha256']) ??
          request.declaredSignatureSha256,
      declaredContainsSecrets: containsSecrets,
      configs: configs,
      fatalError: null,
    );
  }

  factory ThirdPartyImportPayload._fatal(
    ThirdPartyImportRequest request,
    String message,
  ) {
    return ThirdPartyImportPayload(
      request: request,
      schemaVersion: null,
      sourceAppName: null,
      sourcePackageName: null,
      declaredSignatureSha256: null,
      declaredContainsSecrets: false,
      configs: const [],
      fatalError: message,
    );
  }

  bool get hasFatalError => fatalError != null;

  List<ThirdPartyImportConfigCandidate> get validConfigs =>
      configs.where((config) => config.isValid).toList(growable: false);

  List<ThirdPartyImportConfigCandidate> get invalidConfigs =>
      configs.where((config) => !config.isValid).toList(growable: false);

  bool get containsSecrets =>
      declaredContainsSecrets || configs.any((config) => config.containsApiKey);

  String get displaySourceName =>
      request.sourceAppName ??
      request.sourceName ??
      sourceAppName ??
      sourcePackageName ??
      request.sourcePackage ??
      '未知第三方 App';

  String get displaySourcePackage =>
      request.sourcePackage ?? sourcePackageName ?? '未提供';

  String get trustLevel {
    final nativeSignature = request.signatureSha256?.toUpperCase();
    final declaredSignature = declaredSignatureSha256?.toUpperCase();
    if (request.sourceIdentity == ThirdPartySourceIdentity.callingPackage &&
        nativeSignature != null &&
        declaredSignature != null &&
        nativeSignature == declaredSignature) {
      return ApiImportTrustLevels.signatureVerified;
    }
    if (request.sourceIdentity == ThirdPartySourceIdentity.callingPackage &&
        request.sourcePackage != null) {
      return ApiImportTrustLevels.systemPackage;
    }
    if (sourcePackageName != null || request.sourceName != null) {
      return ApiImportTrustLevels.declared;
    }
    return ApiImportTrustLevels.unknown;
  }

  static Object? _decodeJson(String rawPayload) {
    try {
      return jsonDecode(rawPayload);
    } catch (_) {
      return null;
    }
  }
}

abstract final class ThirdPartySourceIdentity {
  static const callingPackage = 'calling_package';
  static const referrer = 'referrer';
}

class ThirdPartyImportConfigCandidate {
  final int index;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String environment;
  final String? group;
  final List<String> tags;
  final Map<String, dynamic>? metadata;
  final String providerId;
  final String protocolId;
  final String? selectedModel;
  final String modelCatalogMode;
  final String modelSource;
  final DateTime? modelsRefreshedAt;
  final List<String> errors;

  const ThirdPartyImportConfigCandidate({
    required this.index,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    required this.environment,
    required this.group,
    required this.tags,
    required this.metadata,
    required this.providerId,
    required this.protocolId,
    required this.selectedModel,
    required this.modelCatalogMode,
    required this.modelSource,
    required this.modelsRefreshedAt,
    required this.errors,
  });

  factory ThirdPartyImportConfigCandidate.fromJson(
    Object? raw,
    int index, {
    required int schemaVersion,
  }) {
    if (raw is! Map) {
      return ThirdPartyImportConfigCandidate._invalid(
        index,
        '配置必须是 JSON 对象',
      );
    }
    if (schemaVersion == 2) {
      return ThirdPartyImportConfigCandidate._fromV2(_readMap(raw), index);
    }
    return ThirdPartyImportConfigCandidate._fromV1(_readMap(raw), index);
  }

  factory ThirdPartyImportConfigCandidate._fromV1(
    Map<String, dynamic> data,
    int index,
  ) {
    final errors = <String>[];
    final name = _readString(data['name']) ?? '';
    final baseUrl = _readString(data['baseUrl']) ?? '';
    final apiKey = _readString(data['apiKey']) ?? '';
    final models = _readStringList(data['models'], errors, 'models');
    final environment = _readString(data['environment']) ?? 'development';
    final tags = _readStringList(data['tags'], errors, 'tags', required: false);
    final group = _readString(data['group']);
    final profile = ApiProfileRegistry.resolve(baseUrl: baseUrl);

    _validateConnection(name, baseUrl, errors);
    if (models.isEmpty) errors.add('models 至少需要 1 个模型');

    return ThirdPartyImportConfigCandidate(
      index: index,
      name: name.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      models: models,
      environment: _normalizedEnvironment(environment),
      group: _normalizedOptional(group),
      tags: tags,
      metadata: _readMapOrNull(data['metadata']),
      providerId: profile.providerId,
      protocolId: profile.protocolId,
      selectedModel: models.isEmpty ? null : models.first,
      modelCatalogMode: ApiModelCatalogModes.saved,
      modelSource: ApiModelSources.manual,
      modelsRefreshedAt: null,
      errors: errors,
    );
  }

  factory ThirdPartyImportConfigCandidate._fromV2(
    Map<String, dynamic> data,
    int index,
  ) {
    final errors = <String>[];
    final connection = _readMap(data['connection']);
    final modelsData = _readMap(data['models']);
    final provider = _readMap(data['provider']);
    final protocol = _readMap(data['protocol']);
    final secrets = _readMap(data['secrets']);
    final name = _readString(connection['name']) ?? '';
    final baseUrl = _readString(connection['baseUrl']) ?? '';
    final models = _readStringList(
      modelsData['availableModels'],
      errors,
      'models.availableModels',
      required: false,
    );
    final selectedModel = _readString(modelsData['selectedModel']);
    final profile = ApiProfileRegistry.resolve(
      baseUrl: baseUrl,
      providerId: _readString(provider['id']),
      protocolId: _readString(protocol['id']),
    );

    _validateConnection(name, baseUrl, errors);
    final modelCatalogMode = _readString(modelsData['catalogMode']) ??
        (models.isEmpty
            ? ApiModelCatalogModes.none
            : ApiModelCatalogModes.saved);
    final modelSource = _readString(modelsData['source']) ??
        (models.isEmpty ? ApiModelSources.unknown : ApiModelSources.thirdParty);

    return ThirdPartyImportConfigCandidate(
      index: index,
      name: name.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: _readString(secrets['apiKey']) ?? '',
      models: models,
      environment: _normalizedEnvironment(
        _readString(connection['environment']) ?? 'development',
      ),
      group: _normalizedOptional(_readString(connection['group'])),
      tags: _readStringList(connection['tags'], errors, 'connection.tags',
          required: false),
      metadata: <String, dynamic>{
        ...?_readMapOrNull(data['metadata']),
        if (_readMapOrNull(data['origin']) != null)
          'declaredOrigin': _readMapOrNull(data['origin']),
      },
      providerId: profile.providerId,
      protocolId: profile.protocolId,
      selectedModel: selectedModel ?? (models.isEmpty ? null : models.first),
      modelCatalogMode: modelCatalogMode,
      modelSource: modelSource,
      modelsRefreshedAt: DateTime.tryParse(
        _readString(modelsData['refreshedAt']) ?? '',
      ),
      errors: errors,
    );
  }

  factory ThirdPartyImportConfigCandidate._invalid(int index, String error) {
    return ThirdPartyImportConfigCandidate(
      index: index,
      name: '第 ${index + 1} 条配置',
      baseUrl: '',
      apiKey: '',
      models: const [],
      environment: 'development',
      group: null,
      tags: const [],
      metadata: null,
      providerId: ApiProviderIds.custom,
      protocolId: ApiProtocolIds.openAiCompatible,
      selectedModel: null,
      modelCatalogMode: ApiModelCatalogModes.none,
      modelSource: ApiModelSources.unknown,
      modelsRefreshedAt: null,
      errors: <String>[error],
    );
  }

  bool get isValid => errors.isEmpty;

  bool get containsApiKey => apiKey.trim().isNotEmpty;

  int get _displayIndex => index + 1;

  String get displayName => name.isEmpty ? '第 $_displayIndex 条配置' : name;

  ApiConfig toApiConfig({
    required String id,
    required String importNameSuffix,
    required DateTime importedAt,
    required Map<String, dynamic> importMetadata,
  }) {
    final mergedMetadata = <String, dynamic>{
      ...?metadata,
      ...importMetadata,
    };

    return ApiConfig(
      id: id,
      name: '$name$importNameSuffix',
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
      environment: environment,
      group: group,
      tags: tags,
      createdAt: importedAt,
      updatedAt: importedAt,
      metadata: mergedMetadata,
      providerId: providerId,
      protocolId: protocolId,
      selectedModel: selectedModel,
      modelCatalogMode: modelCatalogMode,
      modelSource: modelSource,
      modelsRefreshedAt: modelsRefreshedAt,
      importSourceName: _readString(importMetadata['sourceName']),
      importSourcePackage: _readString(importMetadata['sourcePackage']),
      importTrustLevel: _readString(importMetadata['trustLevel']),
    );
  }

  bool isPotentialDuplicateOf(ApiConfig existing) {
    return _normalize(existing.name) == _normalize(name) ||
        _normalizeUrl(existing.baseUrl) == _normalizeUrl(baseUrl);
  }

  static void _validateConnection(
    String name,
    String baseUrl,
    List<String> errors,
  ) {
    if (name.trim().isEmpty) {
      errors.add('缺少 name');
    }
    if (baseUrl.trim().isEmpty) {
      errors.add('缺少 baseUrl');
    } else if (!baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      errors.add('baseUrl 必须以 http:// 或 https:// 开头');
    }
  }

  static String _normalizedEnvironment(String value) =>
      value.trim().isEmpty ? 'development' : value.trim();

  static String? _normalizedOptional(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  static String _normalize(String value) => value.trim().toLowerCase();

  static String _normalizeUrl(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _readString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return value.toString();
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? _readMapOrNull(Object? value) {
  if (value == null || value is! Map) return null;
  return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
}

Set<String> _readStringSet(Object? value) {
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }
  if (value is! Iterable) return <String>{};
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toSet();
}

List<String> _readStringList(
  Object? value,
  List<String> errors,
  String fieldName, {
  bool required = true,
}) {
  if (value == null) {
    if (required) errors.add('缺少 $fieldName');
    return const [];
  }
  if (value is! List) {
    errors.add('$fieldName 必须是字符串数组');
    return const [];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
