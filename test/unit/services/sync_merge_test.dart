import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/features/sync/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService database;
  late SyncService service;
  late String dbPath;

  setUp(() async {
    dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'sync_merge_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    database = DatabaseService(dbPath: dbPath);
    await database.initialize();
    service = SyncService(databaseService: database);
  });

  tearDown(() async {
    await database.forceClose();
    await deleteDatabase(dbPath);
  });

  ApiConfig localConfig({DateTime? updatedAt}) {
    return ApiConfig(
      id: 'local-1',
      name: 'Local DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-local',
      models: const ['deepseek-chat'],
      selectedModel: 'deepseek-chat',
      environment: 'development',
      updatedAt: updatedAt ?? DateTime(2026, 9, 1),
    );
  }

  test('newer remote config with the same id overwrites local', () async {
    final local = localConfig();
    await database.insertApiConfig(local);

    final newer = local.copyWith(
      name: 'Remote renamed',
      updatedAt: DateTime(2026, 9, 2),
    );
    final inserted = await service.storeSyncedConfigs([newer]);

    expect(inserted, 0);
    final stored = await database.getApiConfig('local-1');
    expect(stored?.name, 'Remote renamed');
    // 保留本地创建时间，避免时间线被打乱。
    expect(stored?.createdAt, local.createdAt);
  });

  test('older remote config with the same id cannot roll back local edits',
      () async {
    final local = localConfig(updatedAt: DateTime(2026, 9, 10));
    await database.insertApiConfig(local);

    final older = local.copyWith(
      name: 'Stale remote copy',
      selectedModel: null,
      updatedAt: DateTime(2026, 9, 1),
    );
    final inserted = await service.storeSyncedConfigs([older]);

    expect(inserted, 0);
    final stored = await database.getApiConfig('local-1');
    expect(stored?.name, 'Local DeepSeek');
    expect(stored?.selectedModel, 'deepseek-chat');
  });

  test('business-equivalent newer remote updates in place keeping local id',
      () async {
    final local = localConfig();
    await database.insertApiConfig(local);

    // 地址归一化后等价（带尾斜杠）、id 不同、内容更新。
    final remote = local.copyWith(
      id: 'remote-9',
      baseUrl: 'https://api.deepseek.com/v1/',
      name: 'Remote newer name',
      updatedAt: DateTime(2026, 9, 3),
    );
    final inserted = await service.storeSyncedConfigs([remote]);

    expect(inserted, 0);
    final configs = await database.getAllApiConfigs();
    expect(configs, hasLength(1));
    expect(configs.single.id, 'local-1');
    expect(configs.single.name, 'Remote newer name');
  });

  test('config with a new identity is inserted', () async {
    await database.insertApiConfig(localConfig());

    final brandNew = ApiConfig(
      id: 'other-1',
      name: 'Other API',
      baseUrl: 'https://api.other.com/v1',
      apiKey: 'sk-other',
      models: const ['other-model'],
      environment: 'development',
      updatedAt: DateTime(2026, 9, 2),
    );
    final inserted = await service.storeSyncedConfigs([brandNew]);

    expect(inserted, 1);
    expect(await database.getAllApiConfigs(), hasLength(2));
  });
}
