import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/core/models/api_config.dart';
import 'package:path/path.dart' as path;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService', () {
    test('should insert and retrieve API config', () async {
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_1.db');
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
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_2.db');
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
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_3.db');
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
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_api_4.db');
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
  });
}
