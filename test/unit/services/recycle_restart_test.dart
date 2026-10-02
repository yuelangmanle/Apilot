import 'package:api_manager/core/models/api_config.dart';
import 'package:flutter/foundation.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模拟用户报告：软删除 → 重启（关闭再重开数据库）→ 回收站为空、配置复活。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('deleted_at survives database close/reopen (restart simulation)',
      () async {
    final dbPath = p.join('.dart_tool', 'sqflite_common_ffi', 'databases',
        'restart_sim_${DateTime.now().microsecondsSinceEpoch}.db');

    // 第一次"运行"：建库、加配置、软删除
    final first = DatabaseService(dbPath: dbPath);
    await first.initialize();
    final config = ApiConfig(
      id: 'restart-1',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-x',
      models: const ['m'],
      environment: 'development',
    );
    await first.insertApiConfig(config);
    await first.softDeleteApiConfig('restart-1');

    final binAfterDelete = await first.getDeletedApiConfigs();
    final liveAfterDelete = await first.getAllApiConfigs();
    await first.forceClose();

    // 第二次"运行"：重开同一个数据库文件
    final second = DatabaseService(dbPath: dbPath);
    await second.initialize();
    final binAfterRestart = await second.getDeletedApiConfigs();
    final liveAfterRestart = await second.getAllApiConfigs();

    debugPrint('=== 诊断 ===');
    debugPrint('删除后回收站: ${binAfterDelete.length} 条');
    debugPrint('删除后活列表: ${liveAfterDelete.length} 条');
    debugPrint('重启后回收站: ${binAfterRestart.length} 条');
    debugPrint('重启后活列表: ${liveAfterRestart.length} 条');
    if (binAfterRestart.isEmpty && liveAfterRestart.isNotEmpty) {
      final raw = await (await second.database)
          .query('api_configs', where: "id = 'restart-1'");
      debugPrint('原始行 deleted_at = ${raw.first['deleted_at']}');
    }
    expect(binAfterDelete, hasLength(1));
    expect(liveAfterDelete, isEmpty);
    expect(binAfterRestart, hasLength(1), reason: '重启后回收站不应为空');
    expect(liveAfterRestart, isEmpty, reason: '重启后不应复活到主列表');
    await second.forceClose();
    await deleteDatabase(dbPath);
  });

  test('re-inserting a trashed config with same id keeps it in the bin',
      () async {
    final dbPath2 = p.join('.dart_tool', 'sqflite_common_ffi', 'databases',
        'resurrect_${DateTime.now().microsecondsSinceEpoch}.db');
    final database = DatabaseService(dbPath: dbPath2);
    await database.initialize();
    final config = ApiConfig(
      id: 'fixed-id',
      name: 'Trashed',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-1',
      models: const ['m'],
      environment: 'development',
    );
    await database.insertApiConfig(config);
    await database.softDeleteApiConfig('fixed-id');

    // 同 id、不带 deletedAt 的重插（同步/导入路径的典型形态）：
    // 不允许复活，保留回收站标记。
    await database.insertApiConfig(config.copyWith(name: 'Re-imported'));

    expect(await database.getAllApiConfigs(), isEmpty,
        reason: '同 id 重插不应复活回收站配置');
    final bin = await database.getDeletedApiConfigs();
    expect(bin, hasLength(1));
    expect(bin.single.name, 'Re-imported');

    await database.forceClose();
    await deleteDatabase(dbPath2);
  });


  test('softDeleteApiConfig verifies the write took effect (read-back)',
      () async {
    final ownDbPath =
        '.dart_tool/sqflite_common_ffi/databases/readback_${DateTime.now().microsecondsSinceEpoch}.db';
    final database = DatabaseService(dbPath: ownDbPath);
    await database.initialize();
    final config = ApiConfig(
      id: 'verify-1',
      name: 'Verify',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-v',
      models: const ['m'],
      environment: 'development',
    );
    await database.insertApiConfig(config);
    await database.softDeleteApiConfig('verify-1');

    // 删除后：活列表为空、回收站有 1 条。
    expect(await database.getAllApiConfigs(), isEmpty);
    expect(await database.getDeletedApiConfigs(), hasLength(1));

    // 删除不存在的 id 必须抛错（绝不静默成功）。
    expect(() => database.softDeleteApiConfig('ghost'),
        throwsA(isA<StateError>()));

    // 恢复后回到活列表。
    await database.restoreApiConfig('verify-1');
    expect(await database.getAllApiConfigs(), hasLength(1));
    expect(await database.getDeletedApiConfigs(), isEmpty);

    await database.forceClose();
    await deleteDatabase(ownDbPath);
  });
}
