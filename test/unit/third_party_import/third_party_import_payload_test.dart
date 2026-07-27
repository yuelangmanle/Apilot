import 'dart:convert';

import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/features/third_party_import/models/third_party_import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThirdPartyImportPayload', () {
    test('parses payload with api key', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 1,
            'source': {
              'appName': 'Example Client',
              'packageName': 'com.example.client',
            },
            'options': {'containsSecrets': true},
            'apiConfigs': [
              {
                'name': 'OpenAI Production',
                'baseUrl': 'https://api.openai.com/v1',
                'apiKey': 'sk-test',
                'models': ['gpt-4.1', 'gpt-4.1-mini'],
                'environment': 'production',
                'group': 'AI',
                'tags': ['openai', 'prod'],
              },
            ],
          }),
        ),
      );

      expect(payload.hasFatalError, isFalse);
      expect(payload.displaySourceName, 'Example Client');
      expect(payload.containsSecrets, isTrue);
      expect(payload.validConfigs, hasLength(1));
      expect(payload.validConfigs.first.containsApiKey, isTrue);
      expect(payload.validConfigs.first.models, ['gpt-4.1', 'gpt-4.1-mini']);
    });

    test('supports payload without api key', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 1,
            'apiConfigs': [
              {
                'name': 'No Key',
                'baseUrl': 'https://api.example.com/v1',
                'models': ['demo'],
              },
            ],
          }),
        ),
      );

      expect(payload.hasFatalError, isFalse);
      expect(payload.containsSecrets, isFalse);
      expect(payload.validConfigs.first.apiKey, isEmpty);
      expect(payload.validConfigs.first.environment, 'development');
    });

    test('ignores external id when creating ApiConfig', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 1,
            'apiConfigs': [
              {
                'id': 'external-id',
                'name': 'Imported',
                'baseUrl': 'https://api.example.com/v1',
                'models': ['demo'],
              },
            ],
          }),
        ),
      );

      final config = payload.validConfigs.first.toApiConfig(
        id: 'new-id',
        importNameSuffix: '（导入 2026-07-27 12:00）',
        importedAt: DateTime(2026, 7, 27, 12),
        importMetadata: const {'sourceName': 'Test'},
      );

      expect(config.id, 'new-id');
      expect(config.name, 'Imported（导入 2026-07-27 12:00）');
    });

    test('marks invalid config without blocking valid configs', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 1,
            'apiConfigs': [
              {
                'name': 'Valid',
                'baseUrl': 'https://api.example.com/v1',
                'models': ['demo'],
              },
              {
                'name': '',
                'baseUrl': 'ftp://invalid.example.com',
                'models': [],
              },
            ],
          }),
        ),
      );

      expect(payload.hasFatalError, isFalse);
      expect(payload.validConfigs, hasLength(1));
      expect(payload.invalidConfigs, hasLength(1));
      expect(payload.invalidConfigs.first.errors, contains('缺少 name'));
      expect(
        payload.invalidConfigs.first.errors,
        contains('baseUrl 必须以 http:// 或 https:// 开头'),
      );
    });

    test('rejects unsupported schema version', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 3,
            'apiConfigs': [],
          }),
        ),
      );

      expect(payload.hasFatalError, isTrue);
      expect(payload.fatalError, '导入格式版本不支持');
    });

    test('parses V2 DeepSeek profile without a model catalog', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 2,
            'source': {
              'appName': 'Example Client',
              'packageName': 'com.example.client',
            },
            'apiProfiles': [
              {
                'connection': {
                  'name': 'DeepSeek Primary',
                  'baseUrl': 'https://api.deepseek.com/v1',
                },
                'provider': {'id': 'deepseek'},
                'protocol': {'id': 'openai_compatible'},
                'models': {
                  'selectedModel': 'deepseek-chat',
                  'catalogMode': 'remote',
                  'source': 'third_party',
                },
                'secrets': {'apiKey': 'sk-deepseek'},
              },
            ],
          }),
        ),
      );

      expect(payload.hasFatalError, isFalse);
      expect(payload.schemaVersion, 2);
      expect(payload.validConfigs, hasLength(1));
      final config = payload.validConfigs.single;
      expect(config.providerId, 'deepseek');
      expect(config.protocolId, 'openai_compatible');
      expect(config.selectedModel, 'deepseek-chat');
      expect(config.models, isEmpty);
      expect(config.modelCatalogMode, 'remote');
      expect(config.apiKey, 'sk-deepseek');
    });

    test('V2 infers a provider and uses custom when the endpoint is unknown',
        () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 2,
            'apiProfiles': [
              {
                'connection': {
                  'name': 'Unknown Gateway',
                  'baseUrl': 'https://gateway.example.com/v1',
                },
              },
            ],
          }),
        ),
      );

      expect(payload.hasFatalError, isFalse);
      expect(payload.validConfigs.single.providerId, 'custom');
      expect(
        payload.validConfigs.single.protocolId,
        'openai_compatible',
      );
    });

    test('detects secrets even if caller flag is false', () {
      final payload = ThirdPartyImportPayload.parse(
        _request(
          jsonEncode({
            'schemaVersion': 1,
            'options': {'containsSecrets': false},
            'apiConfigs': [
              {
                'name': 'Secret',
                'baseUrl': 'https://api.example.com/v1',
                'apiKey': 'secret-key',
                'models': ['demo'],
              },
            ],
          }),
        ),
      );

      expect(payload.containsSecrets, isTrue);
    });

    test('marks a source as signature verified only when signatures match', () {
      final request = ThirdPartyImportRequest(
        openDocs: false,
        payload: jsonEncode({
          'schemaVersion': 2,
          'source': {'signatureSha256': 'AA:BB'},
          'apiProfiles': [
            {
              'connection': {
                'name': 'DeepSeek',
                'baseUrl': 'https://api.deepseek.com/v1',
              },
            },
          ],
        }),
        error: null,
        sourceName: 'Example Client',
        sourcePackage: 'com.example.client',
        sourceAppName: 'Example Client',
        signatureSha256: 'aa:bb',
        sourceIdentity: 'calling_package',
        declaredSignatureSha256: null,
        requestId: 'signature-request',
        mimeType: null,
        dataUri: null,
        receivedAt: DateTime(2026, 7, 27),
      );

      final payload = ThirdPartyImportPayload.parse(request);

      expect(payload.trustLevel, 'signature_verified');
    });
  });

  group('ThirdPartyApiConfigPickPayload', () {
    final api = ApiConfig(
      id: 'local-only-id',
      name: 'OpenAI Production',
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-test',
      models: const ['gpt-4.1', 'gpt-4.1-mini'],
      environment: 'production',
      tags: const ['openai', 'prod'],
    );

    test('all mode returns every model and selects the first model by default',
        () {
      final payload = ThirdPartyApiConfigPickPayload.fromApiConfig(
        api,
        modelMode: ThirdPartyModelTransferMode.all,
      ).toJson();

      expect(payload['selectedModel'], 'gpt-4.1');
      expect(payload['modelMode'], 'all');
      expect(
        (payload['apiConfig'] as Map<String, dynamic>)['models'],
        ['gpt-4.1', 'gpt-4.1-mini'],
      );
    });

    test(
        'default-only mode returns the first model without exposing a model list',
        () {
      final payload = ThirdPartyApiConfigPickPayload.fromApiConfig(
        api,
        modelMode: ThirdPartyModelTransferMode.defaultOnly,
      ).toJson();

      expect(payload['selectedModel'], 'gpt-4.1');
      expect(payload['modelMode'], 'default_only');
      expect(
        (payload['apiConfig'] as Map<String, dynamic>).containsKey('models'),
        isFalse,
      );
    });

    test('V2 keeps the key private unless secret.api_key is granted', () {
      final payload = ThirdPartyApiConfigPickPayload.fromApiConfig(
        api.copyWith(
          providerId: 'deepseek',
          selectedModel: 'deepseek-chat',
          modelCatalogMode: 'remote',
          modelSource: 'refreshed',
          modelsRefreshedAt: DateTime(2026, 7, 27, 10),
        ),
        request: const ThirdPartyApiConfigPickRequest.v2(
          sourceName: 'Example Client',
          sourcePackage: 'com.example.client',
          sourceAppName: 'Example Client',
          signatureSha256: null,
          requestId: 'request-v2',
          requestedScopes: {'connection', 'models.default', 'models.all'},
          returnTransport: ThirdPartyResultTransport.extra,
        ),
        grantedScopes: const {'connection', 'models.default', 'models.all'},
      ).toJson();

      final profile = payload['apiProfile'] as Map<String, dynamic>;
      expect(payload['schemaVersion'], 2);
      expect(payload['grantedScopes'],
          ['connection', 'models.default', 'models.all']);
      expect((profile['secrets'] as Map<String, dynamic>).containsKey('apiKey'),
          isFalse);
      expect((profile['models'] as Map<String, dynamic>)['selectedModel'],
          'deepseek-chat');
      expect((profile['models'] as Map<String, dynamic>)['availableModels'],
          ['gpt-4.1', 'gpt-4.1-mini']);
      expect((profile['provider'] as Map<String, dynamic>)['id'], 'deepseek');
    });

    test('V2 returns the key only after secret.api_key is granted', () {
      final payload = ThirdPartyApiConfigPickPayload.fromApiConfig(
        api,
        request: const ThirdPartyApiConfigPickRequest.v2(
          sourceName: 'Example Client',
          sourcePackage: 'com.example.client',
          sourceAppName: 'Example Client',
          signatureSha256: null,
          requestId: 'request-v2-key',
          requestedScopes: {'connection', 'secret.api_key'},
          returnTransport: ThirdPartyResultTransport.extra,
        ),
        grantedScopes: const {'connection', 'secret.api_key'},
      ).toJson();

      final profile = payload['apiProfile'] as Map<String, dynamic>;
      expect(
        (profile['secrets'] as Map<String, dynamic>)['apiKey'],
        'sk-test',
      );
      expect(
        (profile['models'] as Map<String, dynamic>)['availableModels'],
        isNull,
      );
    });

    test('V2 defaults to connection and default model scopes', () {
      final payload = ThirdPartyApiConfigPickPayload.fromApiConfig(
        api,
        request: const ThirdPartyApiConfigPickRequest.v2(
          sourceName: 'Example Client',
          sourcePackage: 'com.example.client',
          sourceAppName: 'Example Client',
          signatureSha256: null,
          requestId: 'request-v2-defaults',
        ),
      ).toJson();

      final profile = payload['apiProfile'] as Map<String, dynamic>;
      expect(payload['grantedScopes'], ['connection', 'models.default']);
      expect((profile['connection'] as Map<String, dynamic>)['baseUrl'],
          'https://api.openai.com/v1');
      expect((profile['models'] as Map<String, dynamic>)['selectedModel'],
          'gpt-4.1');
      expect((profile['secrets'] as Map<String, dynamic>).isEmpty, isTrue);
    });
  });
}

ThirdPartyImportRequest _request(String payload) {
  return ThirdPartyImportRequest(
    openDocs: false,
    payload: payload,
    error: null,
    sourceName: 'Example Client',
    sourcePackage: null,
    sourceAppName: null,
    signatureSha256: null,
    requestId: 'request-1',
    mimeType: 'application/vnd.apilot.api-configs+json',
    dataUri: null,
    receivedAt: DateTime(2026, 7, 27),
  );
}
