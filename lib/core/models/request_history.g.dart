// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RequestHistory _$RequestHistoryFromJson(Map<String, dynamic> json) =>
    RequestHistory(
      id: json['id'] as String,
      apiConfigId: json['apiConfigId'] as String,
      model: json['model'] as String,
      endpoint: json['endpoint'] as String,
      requestBody: json['requestBody'] as Map<String, dynamic>,
      responseBody: json['responseBody'] as Map<String, dynamic>?,
      statusCode: (json['statusCode'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$RequestHistoryToJson(RequestHistory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'apiConfigId': instance.apiConfigId,
      'model': instance.model,
      'endpoint': instance.endpoint,
      'requestBody': instance.requestBody,
      'responseBody': instance.responseBody,
      'statusCode': instance.statusCode,
      'duration': instance.duration,
      'createdAt': instance.createdAt.toIso8601String(),
    };
