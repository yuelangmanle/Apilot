// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      platform: json['platform'] as String,
      ipAddress: json['ipAddress'] as String,
      lastSeen: json['lastSeen'] == null
          ? null
          : DateTime.parse(json['lastSeen'] as String),
      isOnline: json['isOnline'] as bool? ?? true,
    );

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'platform': instance.platform,
      'ipAddress': instance.ipAddress,
      'lastSeen': instance.lastSeen.toIso8601String(),
      'isOnline': instance.isOnline,
    };
