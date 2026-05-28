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
    };
