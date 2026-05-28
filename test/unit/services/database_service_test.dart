import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/core/models/api_config.dart';

void main() {
  late DatabaseService databaseService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseService = DatabaseService();
    await databaseService.initialize();
  });

  tearDown(() async {
    await databaseService.close();
  });

  group('DatabaseService', () {
    test('should insert and retrieve API config', () async {
      final api = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);
      final retrieved = await databaseService.getApiConfig('1');

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'DeepSeek');
    });

    test('should update API config', () async {
      final api = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);

      final updated = api.copyWith(name: 'DeepSeek Updated');
      await databaseService.updateApiConfig(updated);

      final retrieved = await databaseService.getApiConfig('1');
      expect(retrieved!.name, 'DeepSeek Updated');
    });

    test('should delete API config', () async {
      final api = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      await databaseService.insertApiConfig(api);
      await databaseService.deleteApiConfig('1');

      final retrieved = await databaseService.getApiConfig('1');
      expect(retrieved, isNull);
    });

    test('should get all API configs', () async {
      final api1 = ApiConfig(
        id: '1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-test',
        models: ['deepseek-chat'],
        environment: 'development',
      );

      final api2 = ApiConfig(
        id: '2',
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
    });
  });
}
