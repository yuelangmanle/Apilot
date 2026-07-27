// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiConfig _$ApiConfigFromJson(Map<String, dynamic> json) => ApiConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      models:
          (json['models'] as List<dynamic>).map((e) => e as String).toList(),
      environment: json['environment'] as String,
      group: json['group'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      providerId: json['providerId'] as String? ?? ApiProviderIds.custom,
      protocolId:
          json['protocolId'] as String? ?? ApiProtocolIds.openAiCompatible,
      selectedModel: json['selectedModel'] as String?,
      modelCatalogMode:
          json['modelCatalogMode'] as String? ?? ApiModelCatalogModes.saved,
      modelSource: json['modelSource'] as String? ?? ApiModelSources.manual,
      modelsRefreshedAt: json['modelsRefreshedAt'] == null
          ? null
          : DateTime.parse(json['modelsRefreshedAt'] as String),
      importSourceName: json['importSourceName'] as String?,
      importSourcePackage: json['importSourcePackage'] as String?,
      importTrustLevel: json['importTrustLevel'] as String?,
    );

Map<String, dynamic> _$ApiConfigToJson(ApiConfig instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'baseUrl': instance.baseUrl,
      'apiKey': instance.apiKey,
      'models': instance.models,
      'environment': instance.environment,
      'group': instance.group,
      'tags': instance.tags,
      'isFavorite': instance.isFavorite,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'metadata': instance.metadata,
      'providerId': instance.providerId,
      'protocolId': instance.protocolId,
      'selectedModel': instance.selectedModel,
      'modelCatalogMode': instance.modelCatalogMode,
      'modelSource': instance.modelSource,
      'modelsRefreshedAt': instance.modelsRefreshedAt?.toIso8601String(),
      'importSourceName': instance.importSourceName,
      'importSourcePackage': instance.importSourcePackage,
      'importTrustLevel': instance.importTrustLevel,
    };
