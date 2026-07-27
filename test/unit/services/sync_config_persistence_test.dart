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

  test('stores only API configurations with a new business identity', () async {
    final dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'sync_config_persistence_test.db',
    );
    await deleteDatabase(dbPath);
    final database = DatabaseService(dbPath: dbPath);
    await database.initialize();
    final existing = ApiConfig(
      id: 'existing',
      name: 'Existing DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1/',
      apiKey: 'sk-same',
      models: const ['deepseek-chat'],
      selectedModel: 'deepseek-chat',
      environment: 'development',
    );
    await database.insertApiConfig(existing);
    final service = SyncService(databaseService: database);

    final inserted = await service.storeSyncedConfigs([
      existing.copyWith(id: 'same-service-different-id', name: 'Remote copy'),
      existing.copyWith(
        id: 'different-model',
        selectedModel: 'deepseek-reasoner',
        models: const ['deepseek-reasoner'],
      ),
    ]);

    expect(inserted, 1);
    expect(await database.getAllApiConfigs(), hasLength(2));

    await database.forceClose();
    await deleteDatabase(dbPath);
  });
}
