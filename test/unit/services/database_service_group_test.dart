import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/core/models/group.dart';
import 'package:path/path.dart' as path;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService - Group Operations', () {
    test('should insert and retrieve group', () async {
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_group_1.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      
      final group = Group(
        id: 'group_test_1',
        name: 'LLM APIs',
        description: 'Large Language Model APIs',
        color: '#4A90E2',
        sortOrder: 0,
      );

      await databaseService.insertGroup(group);
      final retrieved = await databaseService.getGroup('group_test_1');

      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'LLM APIs');
      expect(retrieved.description, 'Large Language Model APIs');
      expect(retrieved.color, '#4A90E2');
      
      await databaseService.deleteGroup('group_test_1');
      await databaseService.forceClose();
    });

    test('should get all groups', () async {
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_group_2.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      
      final group1 = Group(id: 'g_all_1', name: 'LLM', sortOrder: 0);
      final group2 = Group(id: 'g_all_2', name: 'TTS', sortOrder: 1);

      await databaseService.insertGroup(group1);
      await databaseService.insertGroup(group2);

      final groups = await databaseService.getAllGroups();
      expect(groups.length, 2);
      
      await databaseService.deleteGroup('g_all_1');
      await databaseService.deleteGroup('g_all_2');
      await databaseService.forceClose();
    });

    test('should update group', () async {
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_group_3.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      
      final group = Group(id: 'g_upd_1', name: 'LLM', sortOrder: 0);
      await databaseService.insertGroup(group);

      final updated = Group(
        id: 'g_upd_1',
        name: 'Updated LLM',
        description: 'Updated description',
        sortOrder: 1,
      );
      await databaseService.updateGroup(updated);

      final retrieved = await databaseService.getGroup('g_upd_1');
      expect(retrieved!.name, 'Updated LLM');
      expect(retrieved.description, 'Updated description');
      
      await databaseService.deleteGroup('g_upd_1');
      await databaseService.forceClose();
    });

    test('should delete group', () async {
      final dbPath = path.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'test_group_4.db');
      final databaseService = DatabaseService(dbPath: dbPath);
      await databaseService.initialize();
      
      final group = Group(id: 'g_del_1', name: 'LLM', sortOrder: 0);
      await databaseService.insertGroup(group);

      await databaseService.deleteGroup('g_del_1');
      final retrieved = await databaseService.getGroup('g_del_1');
      expect(retrieved, isNull);
      
      await databaseService.forceClose();
    });
  });
}
