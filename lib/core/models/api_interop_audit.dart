import 'dart:convert';

enum ApiInteropAuditDirection {
  inbound('inbound'),
  outbound('outbound');

  final String wireValue;

  const ApiInteropAuditDirection(this.wireValue);

  static ApiInteropAuditDirection fromWireValue(Object? value) {
    return value == outbound.wireValue ? outbound : inbound;
  }
}

class ApiInteropAudit {
  final String id;
  final ApiInteropAuditDirection direction;
  final DateTime createdAt;
  final String? sourceName;
  final String? sourcePackage;
  final String trustLevel;
  final String? apiConfigId;
  final String apiConfigName;
  final String providerId;
  final String protocolId;
  final List<String> grantedScopes;
  final String? selectedModel;
  final int modelCount;
  final bool apiKeyShared;
  final int schemaVersion;

  const ApiInteropAudit({
    required this.id,
    required this.direction,
    required this.createdAt,
    required this.sourceName,
    required this.sourcePackage,
    required this.trustLevel,
    required this.apiConfigId,
    required this.apiConfigName,
    required this.providerId,
    required this.protocolId,
    required this.grantedScopes,
    required this.selectedModel,
    required this.modelCount,
    required this.apiKeyShared,
    required this.schemaVersion,
  });

  Map<String, Object?> toDatabaseMap() => <String, Object?>{
        'id': id,
        'direction': direction.wireValue,
        'created_at': createdAt.toIso8601String(),
        'source_name': sourceName,
        'source_package': sourcePackage,
        'trust_level': trustLevel,
        'api_config_id': apiConfigId,
        'api_config_name': apiConfigName,
        'provider_id': providerId,
        'protocol_id': protocolId,
        'granted_scopes': jsonEncode(grantedScopes),
        'selected_model': selectedModel,
        'model_count': modelCount,
        'api_key_shared': apiKeyShared ? 1 : 0,
        'schema_version': schemaVersion,
      };

  factory ApiInteropAudit.fromDatabaseMap(Map<String, Object?> map) {
    final scopes = _decodeScopes(map['granted_scopes']);
    return ApiInteropAudit(
      id: map['id'] as String,
      direction: ApiInteropAuditDirection.fromWireValue(map['direction']),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceName: map['source_name'] as String?,
      sourcePackage: map['source_package'] as String?,
      trustLevel: map['trust_level'] as String? ?? 'unknown',
      apiConfigId: map['api_config_id'] as String?,
      apiConfigName: map['api_config_name'] as String? ?? '未命名方案',
      providerId: map['provider_id'] as String? ?? 'custom',
      protocolId: map['protocol_id'] as String? ?? 'openai_compatible',
      grantedScopes: scopes,
      selectedModel: map['selected_model'] as String?,
      modelCount: map['model_count'] as int? ?? 0,
      apiKeyShared: (map['api_key_shared'] as int? ?? 0) == 1,
      schemaVersion: map['schema_version'] as int? ?? 1,
    );
  }

  static List<String> _decodeScopes(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList(growable: false);
      }
    } catch (_) {
      // A malformed audit must not block the user from viewing other records.
    }
    return const [];
  }
}
