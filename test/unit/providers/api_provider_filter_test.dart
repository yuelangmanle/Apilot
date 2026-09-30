
import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/features/api_management/providers/api_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归：v1.22.0 引入的过滤缓存曾漏掉部分 setter 的失效，
/// 导致收藏/排序/分组筛选在界面上毫无反应。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService database;
  late ApiProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = DatabaseService(
      dbPath: p.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'filter_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    provider = ApiProvider(database);
  });

  tearDown(() async {
    await database.forceClose();
    await deleteDatabase(
      p.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
      ),
      // 只删本测试创建的库；目录级删除会波及其他用例。
    );
  });

  ApiConfig config({
    required String id,
    required String name,
    bool favorite = false,
    String? group,
    List<String> tags = const [],
  }) {
    return ApiConfig(
      id: id,
      name: name,
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-$id',
      models: const ['m1'],
      environment: 'development',
      group: group,
      tags: tags,
      isFavorite: favorite,
    );
  }

  test('favorites toggle filters the list', () async {
    await provider.loadApiConfigs();
    expect(provider.apiConfigs, isEmpty);

    await provider.addApiConfig(config(id: 'a', name: 'A'));
    await provider.addApiConfig(config(id: 'b', name: 'B', favorite: true));

    expect(provider.apiConfigs, hasLength(2));
    provider.toggleFavoritesOnly();
    expect(provider.apiConfigs, hasLength(1));
    expect(provider.apiConfigs.single.id, 'b');

    // 再切换回来，必须恢复全量。
    provider.toggleFavoritesOnly();
    expect(provider.apiConfigs, hasLength(2));
  });

  test('group and tag filters work independently', () async {
    await provider.loadApiConfigs();
    await provider.addApiConfig(
        config(id: 'g1', name: 'Grouped', group: 'LLM', tags: ['vision']));
    await provider.addApiConfig(
        config(id: 'g2', name: 'Tagged', tags: ['vision']));
    await provider.addApiConfig(config(id: 'g3', name: 'Plain'));

    provider.setSelectedGroup('LLM');
    expect(provider.apiConfigs, hasLength(1));
    expect(provider.apiConfigs.single.id, 'g1');

    provider.clearAllFilters();
    provider.setSelectedTag('vision');
    expect(provider.apiConfigs.map((c) => c.id).toSet(), {'g1', 'g2'});
    expect(provider.apiConfigs, hasLength(2));
    expect(provider.apiConfigs.every((c) => c.tags.contains('vision')), isTrue);

    provider.clearAllFilters();
    expect(provider.apiConfigs, hasLength(3));
  });

  test('sort by name/created/updated actually reorders', () async {
    await provider.loadApiConfigs();
    final a = config(id: 'a1', name: 'Zebra');
    final b = config(id: 'b1', name: 'Alpha');
    await provider.addApiConfig(a);
    await provider.addApiConfig(b);

    provider.setSortBy('name');
    expect(provider.apiConfigs.first.name, 'Alpha');
    expect(provider.apiConfigs.last.name, 'Zebra');

    // 按更新时间：b 更晚添加（updatedAt 更新），应排最前。
    provider.setSortBy('updated');
    expect(provider.apiConfigs.first.id, 'b1');
  });
}
