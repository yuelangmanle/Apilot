import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/api_interop_audit.dart';
import 'package:path/path.dart' as path;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService', () {
    test('should insert and retrieve API config', () async {
      final dbPath = path.join(
          '.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_1.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();

      final api = ApiConfig(
        id: 'test_1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);
      final retrieved = await databaseService.getApiConfig('test_1');

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'DeepSeek');

      await databaseService.deleteApiConfig('test_1');
      await databaseService.forceClose();
    });

    test('should update API config', () async {
      final dbPath = path.join(
          '.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_2.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();

      final api = ApiConfig(
        id: 'test_2',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);

      final updated = api.copyWith(name: 'DeepSeek Updated');
      await databaseService.updateApiConfig(updated);

      final retrieved = await databaseService.getApiConfig('test_2');
      expect(retrieved!.name, 'DeepSeek Updated');

      await databaseService.deleteApiConfig('test_2');
      await databaseService.forceClose();
    });

    test('should delete API config', () async {
      final dbPath = path.join(
          '.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_3.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();

      final api = ApiConfig(
        id: 'test_3',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);
      await databaseService.deleteApiConfig('test_3');

      final retrieved = await databaseService.getApiConfig('test_3');
      expect(retrieved, isNull);

      await databaseService.forceClose();
    });

    test('should get all API configs', () async {
      final dbPath = path.join(
          '.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_4.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();

      final api1 = ApiConfig(
        id: 'test_4',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      final api2 = ApiConfig(
        id: 'test_5',
        name: 'MiMo',
        baseUrl: 'https://api.mimo.com',
        apiKey: 'sk-test2',
        models: ['mimo-chat'],
        environment: 'production',
      );

      await databaseService.insertApiConfig(api1);
      await databaseService.insertApiConfig(api2);

      final allConfigs = await databaseService.getAllApiConfigs();
      expect(allConfigs.length, 2);

      await databaseService.deleteApiConfig('test_4');
      await databaseService.deleteApiConfig('test_5');
      await databaseService.forceClose();
    });

    test('persists V2 profile fields and JSON metadata', () async {
      final dbPath = path.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'test_api_v2_profile.db',
      );
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      final refreshedAt = DateTime.utc(2026, 7, 27, 10, 30);
      final api = ApiConfig(
        id: 'test_v2',
        name: 'Imported DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        models: const ['deepseek-chat', 'deepseek-reasoner'],
        environment: 'production',
        providerId: 'deepseek',
        protocolId: 'openai_compatible',
        selectedModel: 'deepseek-chat',
        modelCatalogMode: 'remote',
        modelSource: 'third_party',
        modelsRefreshedAt: refreshedAt,
        importSourceName: 'Example Client',
        importSourcePackage: 'com.example.client',
        importTrustLevel: 'signature_verified',
        metadata: const {
          'origin': {'requestId': 'request-v2'},
          'scopes': ['connection', 'models.all'],
        },
      );

      await databaseService.insertApiConfig(api);
      final retrieved = await databaseService.getApiConfig(api.id);

      expect(retrieved, isNotNull);
      expect(retrieved!.providerId, 'deepseek');
      expect(retrieved.protocolId, 'openai_compatible');
      expect(retrieved.selectedModel, 'deepseek-chat');
      expect(retrieved.modelCatalogMode, 'remote');
      expect(retrieved.modelSource, 'third_party');
      expect(retrieved.modelsRefreshedAt, refreshedAt);
      expect(retrieved.importSourceName, 'Example Client');
      expect(retrieved.importTrustLevel, 'signature_verified');
      expect(retrieved.metadata, api.metadata);

      await databaseService.deleteApiConfig(api.id);
      await databaseService.forceClose();
    });

    test('stores and retrieves redacted interoperability audits', () async {
      final dbPath = path.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'test_api_interop_audit.db',
      );
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      final audit = ApiInteropAudit(
        id: 'audit-1',
        direction: ApiInteropAuditDirection.inbound,
        createdAt: DateTime.utc(2026, 7, 27, 12),
        sourceName: 'Example Client',
        sourcePackage: 'com.example.client',
        trustLevel: 'system_package',
        apiConfigId: 'config-1',
        apiConfigName: 'DeepSeek',
        providerId: 'deepseek',
        protocolId: 'openai_compatible',
        grantedScopes: const ['connection', 'models.default'],
        selectedModel: 'deepseek-chat',
        modelCount: 1,
        apiKeyShared: false,
        schemaVersion: 2,
      );

      await databaseService.insertInteropAudit(audit);
      final audits = await databaseService.getInteropAudits();

      expect(audits, hasLength(1));
      expect(audits.single.direction, ApiInteropAuditDirection.inbound);
      expect(audits.single.providerId, 'deepseek');
      expect(audits.single.apiKeyShared, isFalse);
      expect(audits.single.grantedScopes, ['connection', 'models.default']);

      await databaseService.clearInteropAudits();
      await databaseService.forceClose();
    });

    test('migrates a V1 database without losing API configurations', () async {
      final dbPath = path.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'test_api_v1_migration.db',
      );
      await deleteDatabase(dbPath);
      final legacyDatabase = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE api_configs (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              base_url TEXT NOT NULL,
              api_key TEXT NOT NULL,
              models TEXT NOT NULL DEFAULT '',
              environment TEXT NOT NULL DEFAULT 'development',
              api_group TEXT,
              tags TEXT,
              is_favorite INTEGER DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              metadata TEXT
            )
          ''');
          await db.execute('''
            INSERT INTO api_configs (
              id, name, base_url, api_key, models, environment,
              created_at, updated_at, metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
            'legacy-1',
            'Legacy DeepSeek',
            'https://api.deepseek.com/v1',
            'sk-legacy',
            'deepseek-chat,deepseek-reasoner',
            'production',
            '2026-07-01T00:00:00.000Z',
            '2026-07-01T00:00:00.000Z',
            '{legacy: true}',
          ]);
        },
      );
      await legacyDatabase.close();

      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      final migrated = await databaseService.getApiConfig('legacy-1');

      expect(migrated, isNotNull);
      expect(migrated!.models, ['deepseek-chat', 'deepseek-reasoner']);
      expect(migrated.selectedModel, 'deepseek-chat');
      expect(migrated.providerId, 'custom');
      expect(migrated.protocolId, 'openai_compatible');
      expect(migrated.metadata, {'legacyRawMetadata': '{legacy: true}'});

      await databaseService.forceClose();
      await deleteDatabase(dbPath);
    });
  });
}
