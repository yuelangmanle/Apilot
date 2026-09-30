import 'package:json_annotation/json_annotation.dart';

part 'request_history.g.dart';

@JsonSerializable()
class RequestHistory {
  final String id;
  final String apiConfigId;
  final String model;
  final String endpoint;
  final Map<String, dynamic> requestBody;
  final Map<String, dynamic>? responseBody;
  final int? statusCode;
  final int? duration;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cachedTokens;
  final int? reasoningTokens;
  final DateTime createdAt;

  RequestHistory({
    required this.id,
    required this.apiConfigId,
    required this.model,
    required this.endpoint,
    required this.requestBody,
    this.responseBody,
    this.statusCode,
    this.duration,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cachedTokens,
    this.reasoningTokens,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory RequestHistory.fromJson(Map<String, dynamic> json) =>
      _$RequestHistoryFromJson(json);

  Map<String, dynamic> toJson() => _$RequestHistoryToJson(this);
}
