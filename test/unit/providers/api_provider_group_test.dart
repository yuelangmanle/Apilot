import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/models/group.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/features/api_management/providers/api_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('keeps managed form groups separate from legacy filter groups',
      () async {
    final dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'api_provider_group_test.db',
    );
    await deleteDatabase(dbPath);
    final database = DatabaseService(dbPath: dbPath);
    await database.initialize();
    await database.insertGroup(Group(id: 'group_llm', name: 'LLM'));
    await database.insertApiConfig(ApiConfig(
      id: 'legacy_api',
      name: 'Legacy API',
      baseUrl: 'https://legacy.example.com/v1',
      apiKey: 'test-key',
      models: const ['legacy-model'],
      group: '历史分组',
      environment: 'development',
    ));
    final provider = ApiProvider(database);

    await provider.loadApiConfigs();

    expect(provider.availableGroups, ['LLM', '历史分组']);
    expect(provider.managedGroupNames, ['LLM']);

    await database.forceClose();
    await deleteDatabase(dbPath);
  });
}
