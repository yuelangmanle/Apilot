import 'dart:convert';

import '../../../core/models/api_config.dart';

class ThirdPartyImportRequest {
  final bool openDocs;
  final String? payload;
  final String? error;
  final String? sourceName;
  final String? sourcePackage;
  final String? sourceAppName;
  final String? signatureSha256;
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

class ThirdPartyApiConfigPickRequest {
  final String? sourceName;
  final String? sourcePackage;
  final String? sourceAppName;
  final String? signatureSha256;
  final String? requestId;
  final ThirdPartyModelTransferMode modelMode;

  const ThirdPartyApiConfigPickRequest({
    required this.sourceName,
    required this.sourcePackage,
    required this.sourceAppName,
    required this.signatureSha256,
    required this.requestId,
    required this.modelMode,
  });

  factory ThirdPartyApiConfigPickRequest.fromPlatformMap(
    Map<dynamic, dynamic> map,
  ) {
    return ThirdPartyApiConfigPickRequest(
      sourceName: _readString(map['sourceName']),
      sourcePackage: _readString(map['sourcePackage']),
      sourceAppName: _readString(map['sourceAppName']),
      signatureSha256: _readString(map['signatureSha256']),
      requestId: _readString(map['requestId']),
      modelMode: ThirdPartyModelTransferMode.fromWireValue(map['modelMode']),
    );
  }

  String get displaySourceName =>
      sourceAppName ?? sourceName ?? sourcePackage ?? '未知第三方 App';
}

class ThirdPartyApiConfigPickPayload {
  final ApiConfig apiConfig;
  final ThirdPartyModelTransferMode modelMode;

  const ThirdPartyApiConfigPickPayload._({
    required this.apiConfig,
    required this.modelMode,
  });

  factory ThirdPartyApiConfigPickPayload.fromApiConfig(
    ApiConfig apiConfig, {
    required ThirdPartyModelTransferMode modelMode,
  }) {
    return ThirdPartyApiConfigPickPayload._(
      apiConfig: apiConfig,
      modelMode: modelMode,
    );
  }

  String? get selectedModel =>
      apiConfig.models.isEmpty ? null : apiConfig.models.first;

  Map<String, dynamic> toJson() {
    final config = <String, dynamic>{
      'name': apiConfig.name,
      'baseUrl': apiConfig.baseUrl,
      'apiKey': apiConfig.apiKey,
      'environment': apiConfig.environment,
      if (apiConfig.group != null) 'group': apiConfig.group,
      if (apiConfig.tags.isNotEmpty) 'tags': apiConfig.tags,
      if (modelMode == ThirdPartyModelTransferMode.all)
        'models': apiConfig.models,
    };

    return <String, dynamic>{
      'schemaVersion': 1,
      'modelMode': modelMode.wireValue,
      'selectedModel': selectedModel,
      'apiConfig': config,
    };
  }
}

class ThirdPartyImportPayload {
  final ThirdPartyImportRequest request;
  final int? schemaVersion;
  final String? sourceAppName;
  final String? sourcePackageName;
  final bool declaredContainsSecrets;
  final List<ThirdPartyImportConfigCandidate> configs;
  final String? fatalError;

  const ThirdPartyImportPayload({
    required this.request,
    required this.schemaVersion,
    required this.sourceAppName,
    required this.sourcePackageName,
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
    if (schemaVersion != 1) {
      return ThirdPartyImportPayload._fatal(request, '导入格式版本不支持');
    }

    final source = _readMap(decoded['source']);
    final options = _readMap(decoded['options']);
    final rawConfigs = decoded['apiConfigs'];
    if (rawConfigs is! List) {
      return ThirdPartyImportPayload._fatal(request, '导入格式缺少 apiConfigs 列表');
    }
    if (rawConfigs.isEmpty) {
      return ThirdPartyImportPayload._fatal(request, '没有可导入的 API 配置');
    }

    final configs = <ThirdPartyImportConfigCandidate>[];
    for (var i = 0; i < rawConfigs.length; i++) {
      configs.add(ThirdPartyImportConfigCandidate.fromJson(rawConfigs[i], i));
    }

    final declaredContainsSecrets = options['containsSecrets'] == true;
    return ThirdPartyImportPayload(
      request: request,
      schemaVersion: schemaVersion,
      sourceAppName: _readString(source['appName']),
      sourcePackageName: _readString(source['packageName']),
      declaredContainsSecrets: declaredContainsSecrets,
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

  static Object? _decodeJson(String rawPayload) {
    try {
      return jsonDecode(rawPayload);
    } catch (_) {
      return null;
    }
  }
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
    required this.errors,
  });

  factory ThirdPartyImportConfigCandidate.fromJson(Object? raw, int index) {
    final errors = <String>[];
    final displayIndex = index + 1;
    if (raw is! Map) {
      return ThirdPartyImportConfigCandidate(
        index: index,
        name: '第 $displayIndex 条配置',
        baseUrl: '',
        apiKey: '',
        models: const [],
        environment: 'development',
        group: null,
        tags: const [],
        metadata: null,
        errors: const ['配置必须是 JSON 对象'],
      );
    }

    final data = _readMap(raw);
    final name = _readString(data['name']) ?? '';
    final baseUrl = _readString(data['baseUrl']) ?? '';
    final apiKey = _readString(data['apiKey']) ?? '';
    final models = _readStringList(data['models'], errors, 'models');
    final environment = _readString(data['environment']) ?? 'development';
    final tags = _readStringList(data['tags'], errors, 'tags', required: false);
    final group = _readString(data['group']);
    final metadata = _readMapOrNull(data['metadata']);

    if (name.trim().isEmpty) {
      errors.add('缺少 name');
    }
    if (baseUrl.trim().isEmpty) {
      errors.add('缺少 baseUrl');
    } else if (!baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      errors.add('baseUrl 必须以 http:// 或 https:// 开头');
    }
    if (models.isEmpty) {
      errors.add('models 至少需要 1 个模型');
    }

    return ThirdPartyImportConfigCandidate(
      index: index,
      name: name.trim(),
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      models: models,
      environment:
          environment.trim().isEmpty ? 'development' : environment.trim(),
      group: group == null || group.trim().isEmpty ? null : group.trim(),
      tags: tags,
      metadata: metadata,
      errors: errors,
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
    );
  }

  bool isPotentialDuplicateOf(ApiConfig existing) {
    return _normalize(existing.name) == _normalize(name) ||
        _normalizeUrl(existing.baseUrl) == _normalizeUrl(baseUrl);
  }

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
  if (value == null) return null;
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
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
