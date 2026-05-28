import 'package:json_annotation/json_annotation.dart';

part 'api_config.g.dart';

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
    );
  }
}
