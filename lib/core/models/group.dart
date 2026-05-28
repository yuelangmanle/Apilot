import 'package:json_annotation/json_annotation.dart';

part 'group.g.dart';

@JsonSerializable()
class Group {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final int sortOrder;
  final DateTime createdAt;

  Group({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Group.fromJson(Map<String, dynamic> json) =>
      _$GroupFromJson(json);

  Map<String, dynamic> toJson() => _$GroupToJson(this);
}
