import 'package:json_annotation/json_annotation.dart';

part 'device_info.g.dart';

@JsonSerializable()
class DeviceInfo {
  final String id;
  final String name;
  final String platform;
  final String ipAddress;
  final DateTime lastSeen;
  final bool isOnline;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.ipAddress,
    DateTime? lastSeen,
    this.isOnline = true,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);
}
