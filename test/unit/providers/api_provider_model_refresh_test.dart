import 'package:api_manager/core/models/api_config.dart';
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

  test('replaces saved models with the refreshed remote list', () async {
    final dbPath = path.join(
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'api_provider_model_refresh_test.db',
    );
    final database = DatabaseService(dbPath: dbPath);
    await database.initialize();
    final provider = ApiProvider(database);
    final original = ApiConfig(
      id: 'refresh-test',
      name: 'Remote API',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'test-key',
      models: const ['retired-model', 'kept-model'],
      environment: 'development',
      updatedAt: DateTime(2026, 7, 1),
    );
    await provider.addApiConfig(original);

    final refreshed = await provider.replaceApiModels(
      original,
      const ['kept-model', 'new-model'],
    );

    expect(refreshed.models, ['kept-model', 'new-model']);
    expect(await database.getApiConfig(original.id), isNotNull);
    expect(
      (await database.getApiConfig(original.id))!.models,
      ['kept-model', 'new-model'],
    );

    await database.deleteApiConfig(original.id);
    await database.forceClose();
  });
}
