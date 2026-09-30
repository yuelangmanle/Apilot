import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/services/api_key_cipher.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:api_manager/features/sync/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 完整模拟"重启"链路：软删除 → 关库 → 配置密钥（生产 bootstrap 顺序）→
/// 重开 → 回收站同步合并 → 验证不复活。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'FULL RESTART FLOW: trash survives cipher-reconfigure, reopen and sync merge',
      () async {
    final dbPath = '.dart_tool/sqflite_common_ffi/databases/'
        'fullflow_${DateTime.now().microsecondsSinceEpoch}.db';
    final cipher = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());

    // ===== 第一次运行 =====
    DatabaseService.configureCipher(cipher);
    SharedPreferences.setMockInitialValues({});
    final first = DatabaseService(dbPath: dbPath);
    await first.initialize();

    final config = ApiConfig(
      id: 'stable-id',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-live',
      models: const ['deepseek-chat'],
      environment: 'development',
    );
    await first.insertApiConfig(config);
    await first.softDeleteApiConfig('stable-id');
    expect(await first.getDeletedApiConfigs(), hasLength(1));
    await first.forceClose();

    // ===== 重启：bootstrap 顺序（先配密钥，重置共享连接） =====
    DatabaseService.configureCipher(cipher);
    final second = DatabaseService(dbPath: dbPath);
    await second.initialize();

    // 启动清理（retention 默认 7 天，不应误删）
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await second.purgeExpiredApiConfigs(cutoff);

    var bin = await second.getDeletedApiConfigs();
    var live = await second.getAllApiConfigs();
    expect(bin, hasLength(1), reason: '重启后回收站不应为空');
    expect(live, isEmpty, reason: '重启后不应复活到主列表');

    // ===== 同步写入（同 id、更新的数据、无删除标记） =====
    final syncService = SyncService(
      localDeviceIdOverride: 'tester',
      databaseService: second,
    );
    final incoming =
        config.copyWith(name: 'Incoming newer', updatedAt: DateTime.now());
    final inserted = await syncService.storeSyncedConfigs([incoming]);

    expect(inserted, 0);
    bin = await second.getDeletedApiConfigs();
    live = await second.getAllApiConfigs();
    expect(bin, hasLength(1), reason: '同步合并不应复活回收站配置');
    expect(live, isEmpty);
    expect(bin.single.name, 'Incoming newer', reason: '内容应按新者胜更新');

    // ===== 彻底重启一次再验证 =====
    await second.forceClose();
    DatabaseService.configureCipher(cipher);
    final third = DatabaseService(dbPath: dbPath);
    await third.initialize();
    expect(await third.getAllApiConfigs(), isEmpty);
    expect(await third.getDeletedApiConfigs(), hasLength(1));

    await third.forceClose();
    await deleteDatabase(dbPath);
  });
}
