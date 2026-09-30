import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/request_history.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService database;
  late String dbPath;

  setUp(() async {
    dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'recycle_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    database = DatabaseService(dbPath: dbPath);
    await database.initialize();
  });

  tearDown(() async {
    await database.forceClose();
    await deleteDatabase(dbPath);
  });

  Future<ApiConfig> seedConfig(String id, {String name = 'DeepSeek'}) async {
    final config = ApiConfig(
      id: id,
      name: name,
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-$id',
      models: const ['deepseek-chat'],
      environment: 'development',
    );
    await database.insertApiConfig(config);
    return config;
  }

  test('soft delete hides from live list and shows in recycle bin', () async {
    final config = await seedConfig('r1');
    database.insertRequestHistory(_history(config.id));

    await database.softDeleteApiConfig('r1');

    expect(await database.getAllApiConfigs(), isEmpty);
    final deleted = await database.getDeletedApiConfigs();
    expect(deleted, hasLength(1));
    expect(deleted.single.id, 'r1');
    expect(deleted.single.deletedAt, isNotNull);
  });

  test('restore returns the config and keeps history', () async {
    final config = await seedConfig('r2');
    database.insertRequestHistory(_history(config.id, statusCode: 200));
    await database.softDeleteApiConfig('r2');

    await database.restoreApiConfig('r2');

    final restored = await database.getApiConfig('r2');
    expect(restored, isNotNull);
    expect(restored!.deletedAt, isNull);
    expect(await database.getDeletedApiConfigs(), isEmpty);
    final history = await database.getRequestHistory(apiConfigId: 'r2');
    expect(history, hasLength(1));
  });

  test('purge removes config together with its history', () async {
    final config = await seedConfig('r3');
    database.insertRequestHistory(_history(config.id));
    await database.softDeleteApiConfig('r3');

    final purged = await database.purgeApiConfig('r3');

    expect(purged, isTrue);
    expect(await database.getApiConfig('r3'), isNull);
    expect(
        await database.getRequestHistory(apiConfigId: 'r3'), isEmpty);
    expect(await database.getDeletedApiConfigs(), isEmpty);
  });

  test('purgeExpiredApiConfigs only removes items older than cutoff',
      () async {
    await seedConfig('old', name: 'Old');
    await seedConfig('new', name: 'New');

    final db = await database.database;
    final oldCutoff = DateTime.now().subtract(const Duration(days: 10));
    final recent = DateTime.now().subtract(const Duration(hours: 1));
    await db.update(
      'api_configs',
      {'deleted_at': oldCutoff.toIso8601String()},
      where: "id = 'old'",
    );
    await db.update(
      'api_configs',
      {'deleted_at': recent.toIso8601String()},
      where: "id = 'new'",
    );

    final purged =
        await database.purgeExpiredApiConfigs(DateTime.now().subtract(
      const Duration(days: 7),
    ));

    expect(purged, 1);
    final remaining = await database.getDeletedApiConfigs();
    expect(remaining.single.id, 'new');
    expect(await database.getAllApiConfigs(), isEmpty);
  });

  test('clearRecycleBin purges everything but keeps live configs',
      () async {
    await seedConfig('live', name: 'Live');
    await seedConfig('trash1', name: 'Trash 1');
    await seedConfig('trash2', name: 'Trash 2');
    await database.softDeleteApiConfig('trash1');
    await database.softDeleteApiConfig('trash2');

    final purged = await database.clearRecycleBin();

    expect(purged, 2);
    final live = await database.getAllApiConfigs();
    expect(live.single.id, 'live');
    expect(await database.getDeletedApiConfigs(), isEmpty);
  });
}

RequestHistory _history(String configId, {int? statusCode}) {
  return RequestHistory(
    id: 'h-$configId-${statusCode ?? 'na'}',
    apiConfigId: configId,
    model: 'deepseek-chat',
    endpoint: '/chat/completions',
    requestBody: const {},
    statusCode: statusCode,
    duration: 100,
  );
}
