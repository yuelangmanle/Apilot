import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/services/api_key_cipher.dart';
import 'package:api_manager/core/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ApiKeyCipher', () {
    test('round-trips plaintext through the enc1 prefix', () {
      final cipher = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());

      final encrypted = cipher.encrypt('sk-secret-value');
      expect(encrypted, startsWith(ApiKeyCipher.prefix));
      expect(encrypted, isNot(contains('sk-secret-value')));
      expect(cipher.decrypt(encrypted), 'sk-secret-value');
    });

    test('leaves empty and already-encrypted values untouched', () {
      final cipher = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());

      expect(cipher.encrypt(''), '');
      final once = cipher.encrypt('sk-x');
      expect(cipher.encrypt(once), once);
      expect(cipher.decrypt('plaintext-key'), 'plaintext-key');
    });

    test('decrypt with a foreign key degrades instead of throwing', () {
      final cipherA = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());
      final cipherB = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());

      final encrypted = cipherA.encrypt('sk-abc');
      // 密钥不匹配时返回原样密文（占位），不得抛异常拖垮列表加载。
      expect(cipherB.decrypt(encrypted), encrypted);
    });

    test('rejects master keys that are not 32 bytes', () {
      expect(
        () => ApiKeyCipher.fromKeyBase64('AAAA'),
        throwsArgumentError,
      );
    });
  });

  group('DatabaseService encryption integration', () {
    late String dbPath;
    late DatabaseService database;
    late ApiKeyCipher cipher;

    setUp(() async {
      dbPath = path.join(
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'cipher_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      cipher = ApiKeyCipher.fromKeyBase64(generateMasterKeyBase64());
      DatabaseService.configureCipher(cipher);
      database = DatabaseService(dbPath: dbPath);
      await database.initialize();
    });

    tearDown(() async {
      DatabaseService.configureCipher(null);
      await database.forceClose();
      await deleteDatabase(dbPath);
    });

    test('api keys are stored encrypted and read back as plaintext',
        () async {
      final config = ApiConfig(
        id: 'enc-1',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-plain-text-key',
        models: const ['deepseek-chat'],
        environment: 'development',
      );

      await database.insertApiConfig(config);

      final stored = await database.database;
      final rows = await stored
          .query('api_configs', where: 'id = ?', whereArgs: ['enc-1']);
      expect(rows.single['api_key'], startsWith(ApiKeyCipher.prefix));

      final readBack = await database.getApiConfig('enc-1');
      expect(readBack?.apiKey, 'sk-plain-text-key');
    });

    test('updates keep the stored value encrypted', () async {
      final config = ApiConfig(
        id: 'enc-2',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-first',
        models: const [],
        environment: 'development',
      );
      await database.insertApiConfig(config);
      await database.updateApiConfig(
        config.copyWith(apiKey: 'sk-second', updatedAt: DateTime.now()),
      );

      final stored = await database.database;
      final rows = await stored
          .query('api_configs', where: 'id = ?', whereArgs: ['enc-2']);
      expect(rows.single['api_key'], startsWith(ApiKeyCipher.prefix));
      expect((rows.single['api_key'] as String), isNot(contains('sk-second')));

      final readBack = await database.getApiConfig('enc-2');
      expect(readBack?.apiKey, 'sk-second');
    });
  });
}
