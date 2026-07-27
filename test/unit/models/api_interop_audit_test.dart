import 'package:api_manager/core/models/api_interop_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts secrets and stores only authorization facts', () {
    final audit = ApiInteropAudit(
      id: 'audit-1',
      direction: ApiInteropAuditDirection.outbound,
      createdAt: DateTime.utc(2026, 7, 27, 12),
      sourceName: 'Example Client',
      sourcePackage: 'com.example.client',
      trustLevel: 'system_package',
      apiConfigId: 'config-1',
      apiConfigName: 'DeepSeek',
      providerId: 'deepseek',
      protocolId: 'openai_compatible',
      grantedScopes: const ['connection', 'secret.api_key'],
      selectedModel: 'deepseek-chat',
      modelCount: 2,
      apiKeyShared: true,
      schemaVersion: 2,
    );

    final map = audit.toDatabaseMap();

    expect(map.containsKey('api_key'), isFalse);
    expect(map['api_key_shared'], 1);
    expect(map['granted_scopes'], contains('secret.api_key'));
  });
}
