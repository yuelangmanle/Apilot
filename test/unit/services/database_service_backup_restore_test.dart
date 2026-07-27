import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/group.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('replaces APIs and groups from a complete backup snapshot', () async {
    final dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'database_service_backup_restore_test.db',
    );
    await deleteDatabase(dbPath);
    final database = DatabaseService(dbPath: dbPath);
    await database.initialize();
    await database.insertGroup(Group(id: 'old_group', name: '旧分组'));
    await database.insertApiConfig(ApiConfig(
      id: 'old_api',
      name: '旧配置',
      baseUrl: 'https://old.example.com/v1',
      apiKey: 'old-key',
      models: const ['old-model'],
      group: '旧分组',
      environment: 'development',
    ));

    final summary = await database.restoreBackup(
      groups: [Group(id: 'llm_group', name: 'LLM')],
      configs: [
        ApiConfig(
          id: 'deepseek_api',
          name: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-restored',
          models: const ['deepseek-chat'],
          group: 'LLM',
          environment: 'production',
        ),
      ],
      replaceExisting: true,
    );

    expect(summary.groupsRestored, 1);
    expect(summary.configsRestored, 1);
    expect(await database.getApiConfig('old_api'), isNull);
    expect((await database.getAllGroups()).single.name, 'LLM');
    expect((await database.getAllApiConfigs()).single.group, 'LLM');

    await database.forceClose();
    await deleteDatabase(dbPath);
  });
}
