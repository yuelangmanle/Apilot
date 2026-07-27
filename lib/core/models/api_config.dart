import 'package:json_annotation/json_annotation.dart';

import 'api_profile.dart';

part 'api_config.g.dart';

const Object _unsetSelectedModel = Object();

@JsonSerializable()
class ApiConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String environment;
  final String? group;
  final List<String> tags;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;
  final String providerId;
  final String protocolId;
  final String? selectedModel;
  final String modelCatalogMode;
  final String modelSource;
  final DateTime? modelsRefreshedAt;
  final String? importSourceName;
  final String? importSourcePackage;
  final String? importTrustLevel;

  ApiConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    required this.environment,
    this.group,
    this.tags = const [],
    this.isFavorite = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.metadata,
    this.providerId = ApiProviderIds.custom,
    this.protocolId = ApiProtocolIds.openAiCompatible,
    this.selectedModel,
    this.modelCatalogMode = ApiModelCatalogModes.saved,
    this.modelSource = ApiModelSources.manual,
    this.modelsRefreshedAt,
    this.importSourceName,
    this.importSourcePackage,
    this.importTrustLevel,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ApiConfigToJson(this);

  ApiConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    String? environment,
    String? group,
    List<String>? tags,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
    String? providerId,
    String? protocolId,
    Object? selectedModel = _unsetSelectedModel,
    String? modelCatalogMode,
    String? modelSource,
    DateTime? modelsRefreshedAt,
    String? importSourceName,
    String? importSourcePackage,
    String? importTrustLevel,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      environment: environment ?? this.environment,
      group: group ?? this.group,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
      providerId: providerId ?? this.providerId,
      protocolId: protocolId ?? this.protocolId,
      selectedModel: identical(selectedModel, _unsetSelectedModel)
          ? this.selectedModel
          : selectedModel as String?,
      modelCatalogMode: modelCatalogMode ?? this.modelCatalogMode,
      modelSource: modelSource ?? this.modelSource,
      modelsRefreshedAt: modelsRefreshedAt ?? this.modelsRefreshedAt,
      importSourceName: importSourceName ?? this.importSourceName,
      importSourcePackage: importSourcePackage ?? this.importSourcePackage,
      importTrustLevel: importTrustLevel ?? this.importTrustLevel,
    );
  }
}
