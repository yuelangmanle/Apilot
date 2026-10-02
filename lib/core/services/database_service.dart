import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/api_config.dart';
import '../models/api_interop_audit.dart';
import '../models/group.dart';
import '../models/request_history.dart';
import 'api_config_identity.dart';
import 'api_key_cipher.dart';

class BackupRestoreSummary {
  final int configsRestored;
  final int groupsRestored;

  const BackupRestoreSummary({
    required this.configsRestored,
    required this.groupsRestored,
  });
}

/// 默认路径的数据库在进程内共享一个连接；带自定义路径的实例（测试）持有
/// 各自独立的连接。应用生命周期内不要 close 共享连接。
class DatabaseService {
  static Database? _sharedDatabase;
  Database? _ownedDatabase;
  final String? _customDbPath;

  /// 全局静态加密器：应用启动时配置一次，所有实例（含 sync/settings
  /// 临时实例）共用。未配置时（单元测试）保持明文行为。
  static ApiKeyCipher? _cipher;

  static void configureCipher(ApiKeyCipher? cipher) {
    _cipher = cipher;
    _sharedDatabase = null; // 迫使下次访问以新配置重新打开并执行迁移。
  }

  static ApiKeyCipher? get configuredCipher => _cipher;

  DatabaseService({String? dbPath}) : _customDbPath = dbPath;

  Future<Database> get database async {
    final customPath = _customDbPath;
    if (customPath != null) {
      return _ownedDatabase ??= await openDatabase(
        customPath,
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onDowngrade: _onDowngrade,
      );
    }
    return _sharedDatabase ??= await _initializeDatabase();
  }

  /// 降级安装时不删除数据库（sqflite 默认会删库），保留用户数据。
  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[DB] 版本降级 $oldVersion -> $newVersion，保留数据不删库');
  }

  static const int _databaseVersion = 9;

  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final filePath = path.join(dbPath, 'api_manager.db');
    try {
      return await openDatabase(
        filePath,
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onDowngrade: _onDowngrade,
      );
    } on DatabaseException catch (e) {
      // 损坏自愈：把坏文件改名保留（供人工恢复），重建空库让应用可用。
      final code = e.getResultCode();
      final corrupt = code == 11 || code == 26;
      if (!corrupt) rethrow;
      final corruptFile = File('$filePath.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      final source = File(filePath);
      if (source.existsSync()) {
        debugPrint('[DB] 数据库损坏，已备份到 ${corruptFile.path}');
        source.renameSync(corruptFile.path);
      }
      return await openDatabase(
        filePath,
        version: _databaseVersion,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
        onDowngrade: _onDowngrade,
      );
    }
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_configs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        models TEXT NOT NULL DEFAULT '',
        environment TEXT NOT NULL DEFAULT 'development',
        api_group TEXT,
        tags TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        metadata TEXT,
        provider_id TEXT NOT NULL DEFAULT 'custom',
        protocol_id TEXT NOT NULL DEFAULT 'openai_compatible',
        selected_model TEXT,
        model_catalog_mode TEXT NOT NULL DEFAULT 'saved',
        model_source TEXT NOT NULL DEFAULT 'manual',
        models_refreshed_at TEXT,
        import_source_name TEXT,
        import_source_package TEXT,
        import_trust_level TEXT,
        deleted_at TEXT,
        expires_at TEXT,
        low_balance TEXT,
        monthly_budget REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS request_history (
        id TEXT PRIMARY KEY,
        api_config_id TEXT NOT NULL,
        model TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        request_body TEXT NOT NULL DEFAULT '{}',
        response_body TEXT,
        status_code INTEGER,
        duration INTEGER,
        prompt_tokens INTEGER,
        completion_tokens INTEGER,
        total_tokens INTEGER,
        cached_tokens INTEGER,
        reasoning_tokens INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (api_config_id) REFERENCES api_configs (id)
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_history_created ON request_history (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_history_config ON request_history (api_config_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS deleted_config_ids (
        id TEXT PRIMARY KEY,
        deleted_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        color TEXT,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await _createInteropAuditTable(db);
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE api_configs ADD COLUMN provider_id TEXT NOT NULL DEFAULT 'custom'",
      );
      await db.execute(
        "ALTER TABLE api_configs ADD COLUMN protocol_id TEXT NOT NULL DEFAULT 'openai_compatible'",
      );
      await db
          .execute('ALTER TABLE api_configs ADD COLUMN selected_model TEXT');
      await db.execute(
        "ALTER TABLE api_configs ADD COLUMN model_catalog_mode TEXT NOT NULL DEFAULT 'saved'",
      );
      await db.execute(
        "ALTER TABLE api_configs ADD COLUMN model_source TEXT NOT NULL DEFAULT 'manual'",
      );
      await db.execute(
        'ALTER TABLE api_configs ADD COLUMN models_refreshed_at TEXT',
      );
      await db.execute(
        'ALTER TABLE api_configs ADD COLUMN import_source_name TEXT',
      );
      await db.execute(
        'ALTER TABLE api_configs ADD COLUMN import_source_package TEXT',
      );
      await db.execute(
        'ALTER TABLE api_configs ADD COLUMN import_trust_level TEXT',
      );
      await db.execute('''
        UPDATE api_configs
        SET selected_model = CASE
          WHEN instr(models, ',') > 0 THEN substr(models, 1, instr(models, ',') - 1)
          WHEN trim(models) != '' THEN models
          ELSE NULL
        END
        WHERE selected_model IS NULL
      ''');
    }
    if (oldVersion < 3) {
      await _createInteropAuditTable(db);
    }
    // 顺序说明：v4 在 v5 之前仅是历史阅读顺序，二者互不依赖。
    if (oldVersion < 4) {
      final historyTable = await db.query('sqlite_master',
          where: "type = 'table' AND name = 'request_history'");
      if (historyTable.isEmpty) {
        // 极老版本（v1 前）可能没有历史表：直接按新结构建表。
        await db.execute('''
          CREATE TABLE IF NOT EXISTS request_history (
            id TEXT PRIMARY KEY,
            api_config_id TEXT NOT NULL,
            model TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            request_body TEXT NOT NULL DEFAULT '{}',
            response_body TEXT,
            status_code INTEGER,
            duration INTEGER,
            prompt_tokens INTEGER,
            completion_tokens INTEGER,
            total_tokens INTEGER,
            cached_tokens INTEGER,
            reasoning_tokens INTEGER,
            created_at TEXT NOT NULL,
            FOREIGN KEY (api_config_id) REFERENCES api_configs (id)
          )
        ''');
      } else {
        await db.execute(
            'ALTER TABLE request_history ADD COLUMN prompt_tokens INTEGER');
        await db.execute(
            'ALTER TABLE request_history ADD COLUMN completion_tokens INTEGER');
        await db.execute(
            'ALTER TABLE request_history ADD COLUMN total_tokens INTEGER');
      }

      // 一次性把存量明文 API Key 加密；未配置加密器（测试）时跳过。
      final cipher = _cipher;
      if (cipher != null) {
        final rows = await db.query('api_configs', columns: ['id', 'api_key']);
        for (final row in rows) {
          final stored = row['api_key'] as String? ?? '';
          if (stored.isEmpty || stored.startsWith(ApiKeyCipher.prefix)) {
            continue;
          }
          try {
            await db.update(
              'api_configs',
              {'api_key': cipher.encrypt(stored)},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } catch (e) {
            // 单行失败不让整个迁移崩掉：该行保持明文，下次升级重试。
            debugPrint('[DB] 加密存量 Key 失败 id=${row['id']}: $e');
          }
        }
      }
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE api_configs ADD COLUMN deleted_at TEXT');
    }
    if (oldVersion < 9) {
      // 墓碑表：删除 id 的权威记录。api_configs 行被任何写入者改动
      // （更新/重插/合并）都不会影响删除状态，从查询层面杜绝复活。
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_config_ids (
          id TEXT PRIMARY KEY,
          deleted_at TEXT NOT NULL
        )
      ''');
      // 存量回收站内容回填墓碑。
      await db.execute('''
        INSERT OR IGNORE INTO deleted_config_ids (id, deleted_at)
        SELECT id, deleted_at FROM api_configs WHERE deleted_at IS NOT NULL
      ''');
    }
    if (oldVersion < 8) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_history_created ON request_history (created_at DESC)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_history_config ON request_history (api_config_id)');
    }
    if (oldVersion < 7) {
      // v1 缺表场景已在上面按完整结构建表，这里按列是否存在幂等补齐。
      final historyColumns =
          await db.rawQuery('PRAGMA table_info(request_history)');
      final names = historyColumns.map((row) => row['name']).toSet();
      if (!names.contains('cached_tokens')) {
        await db.execute(
            'ALTER TABLE request_history ADD COLUMN cached_tokens INTEGER');
      }
      if (!names.contains('reasoning_tokens')) {
        await db.execute(
            'ALTER TABLE request_history ADD COLUMN reasoning_tokens INTEGER');
      }
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE api_configs ADD COLUMN expires_at TEXT');
      await db.execute('ALTER TABLE api_configs ADD COLUMN low_balance TEXT');
      await db
          .execute('ALTER TABLE api_configs ADD COLUMN monthly_budget REAL');
    }
  }

  Future<void> _createInteropAuditTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_interop_audits (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        created_at TEXT NOT NULL,
        source_name TEXT,
        source_package TEXT,
        trust_level TEXT NOT NULL,
        api_config_id TEXT,
        api_config_name TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        protocol_id TEXT NOT NULL,
        granted_scopes TEXT NOT NULL DEFAULT '[]',
        selected_model TEXT,
        model_count INTEGER NOT NULL DEFAULT 0,
        api_key_shared INTEGER NOT NULL DEFAULT 0,
        schema_version INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> initialize() async {
    await database;
  }

  /// 只关闭本实例自己打开的数据库（自定义路径实例）。共享连接不受影响。
  Future<void> close() async {
    await _ownedDatabase?.close();
    _ownedDatabase = null;
  }

  Future<void> forceClose() async {
    await _ownedDatabase?.close();
    _ownedDatabase = null;
    await _sharedDatabase?.close();
    _sharedDatabase = null;
  }

  // ==================== API Config operations ====================
  Future<void> insertApiConfig(ApiConfig api) async {
    final db = await database;
    // 回收站保护：同 id 的已软删行被重新写入时（同步/导入/备份），
    // 保留回收站标记——任何写入路径都不允许"顺带复活"已删除的配置。
    // 唯一的恢复途径是回收站页的恢复按钮（restoreApiConfig）。
    final existing = await db.query(
      'api_configs',
      columns: ['deleted_at'],
      where: 'id = ?',
      whereArgs: [api.id],
      limit: 1,
    );
    final wasTrashed = existing.isNotEmpty &&
        existing.first['deleted_at'] != null;
    final map = _apiConfigToMap(api);
    if (wasTrashed) {
      final existingDeletedAt = existing.first['deleted_at'] as String?;
      if (api.deletedAt == null) {
        map['deleted_at'] = existingDeletedAt;
      }
    }
    await db.insert(
      'api_configs',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 供同步事务复用的行映射（含 api_key 加密）。
  Map<String, Object?> buildConfigRow(ApiConfig api) => _apiConfigToMap(api);

  Map<String, Object?> _apiConfigToMap(ApiConfig api) {
    final cipher = _cipher;
    final apiKey = cipher == null ? api.apiKey : cipher.encrypt(api.apiKey);
    return {
      'id': api.id,
      'name': api.name,
      'base_url': api.baseUrl,
      'api_key': apiKey,
      'models': api.models.join(','),
      'environment': api.environment,
      'api_group': api.group,
      'tags': api.tags.join(','),
      'is_favorite': api.isFavorite ? 1 : 0,
      'created_at': api.createdAt.toIso8601String(),
      'updated_at': api.updatedAt.toIso8601String(),
      'metadata': _encodeMetadata(api.metadata),
      'provider_id': api.providerId,
      'protocol_id': api.protocolId,
      'selected_model': api.selectedModel,
      'model_catalog_mode': api.modelCatalogMode,
      'model_source': api.modelSource,
      'models_refreshed_at': api.modelsRefreshedAt?.toIso8601String(),
      'import_source_name': api.importSourceName,
      'import_source_package': api.importSourcePackage,
      'import_trust_level': api.importTrustLevel,
      'deleted_at': api.deletedAt?.toIso8601String(),
      'expires_at': api.expiresAt?.toIso8601String(),
      'low_balance': api.lowBalanceThreshold,
      'monthly_budget': api.monthlyBudget,
    };
  }

  Future<ApiConfig?> getApiConfig(String id) async {
    final db = await database;
    final maps = await db.query(
      'api_configs',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    return _mapToApiConfig(maps.first);
  }

  /// 删除墓碑的 SharedPreferences 镜像。
  ///
  /// 墓碑表存在于数据库文件内——换机克隆/系统回滚等外部覆盖会把整个
  /// DB 文件（含墓碑）替换为旧版本，删除记录随之丢失。镜像存在
  /// SharedPreferences（独立文件）中，启动读取时与 DB 做并集聚合：
  /// 只要任一侧记录了删除，该配置就不会复活。
  static const String _mirrorPrefsKey = 'apilot_deleted_config_mirror';

  static Future<Map<String, String>> _readDeletionMirror() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_mirrorPrefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      debugPrint('[DB] 删除镜像读取失败: $e');
      return {};
    }
  }

  static Future<void> _mirrorSet(String id, String deletedAt) async {
    final mirror = await _readDeletionMirror();
    mirror[id] = deletedAt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mirrorPrefsKey, jsonEncode(mirror));
    } catch (e) {
      debugPrint('[DB] 删除镜像写入失败: $e');
    }
  }

  static Future<void> _mirrorRemove(String id) async {
    final mirror = await _readDeletionMirror();
    if (!mirror.containsKey(id)) return;
    mirror.remove(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mirrorPrefsKey, jsonEncode(mirror));
    } catch (_) {}
  }

  static Future<void> _mirrorRemoveAll(Iterable<String> ids) async {
    final mirror = await _readDeletionMirror();
    var changed = false;
    for (final id in ids) {
      if (mirror.remove(id) != null) changed = true;
    }
    if (!changed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mirrorPrefsKey, jsonEncode(mirror));
    } catch (_) {}
  }

  /// 默认只返回存活配置（回收站中的除外）。
  /// [executor] 允许在外层事务内执行同一批读取（同步合并使用）。
  ///
  /// 删除状态以墓碑表 + prefs 镜像的**并集**为权威来源：即使 api_configs
  /// 行或 DB 文件被外部覆盖，镜像仍会把被删配置排除在活列表之外，
  /// 并就地修复（重新打上行标记）。
  Future<List<ApiConfig>> getAllApiConfigs({
    bool includeDeleted = false,
    DatabaseExecutor? executor,
  }) async {
    // 整表查询失败时向上抛出：调用方（列表页/备份/同步服务）需要感知数据库
    // 异常，避免把故障误显示为"没有任何配置"而诱导用户执行清空恢复。
    final db = executor ?? await database;
    final maps = await db.rawQuery('''
      SELECT a.*, COALESCE(t.deleted_at, a.deleted_at) AS effective_deleted_at
      FROM api_configs a
      LEFT JOIN deleted_config_ids t ON t.id = a.id
      ORDER BY a.name ASC
    ''');

    // prefs 镜像并集（DB 被外部覆盖时的最后防线）。
    final mirror = await _readDeletionMirror();

    final List<ApiConfig> results = [];
    final repairs = <String, String>{};
    for (final map in maps) {
      final id = map['id'] as String?;
      try {
        final rowDeleted = map['deleted_at'] as String?;
        final mirrorDeleted = id == null ? null : mirror[id];
        final effectiveDeletedAt =
            mirrorDeleted ?? (map['effective_deleted_at'] as String?);
        if (!includeDeleted && effectiveDeletedAt != null) {
          // 行标记丢失但镜像/墓碑仍在（外部覆盖场景）：就地修复。
          if (executor == null && rowDeleted == null && id != null) {
            repairs[id] = mirrorDeleted ?? effectiveDeletedAt;
          }
          continue;
        }
        final row = Map<String, Object?>.from(map);
        row['deleted_at'] = effectiveDeletedAt;
        results.add(_mapToApiConfig(row));
      } catch (e) {
        debugPrint('跳过损坏的API记录 id=$id: $e');
      }
    }

    // 就地修复复活行（仅在非事务路径执行写操作）。
    if (executor == null) {
      for (final entry in repairs.entries) {
        try {
          await db.update('api_configs',
              {'deleted_at': entry.value}, where: 'id = ?', whereArgs: [entry.key]);
          debugPrint('[DB] 检测到复活行，已重新回收: ${entry.key}');
        } catch (e) {
          debugPrint('[DB] 修复失败 id=${entry.key}: $e');
        }
      }
    }
    return results;
  }

  /// 回收站内容，按删除时间倒序。以墓碑表 + prefs 镜像的并集为准
  /// （行标记被覆盖也能找回）。
  Future<List<ApiConfig>> getDeletedApiConfigs() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT a.*,
             COALESCE(t.deleted_at, a.deleted_at) AS effective_deleted_at
      FROM api_configs a
      LEFT JOIN deleted_config_ids t ON t.id = a.id
      WHERE COALESCE(t.deleted_at, a.deleted_at) IS NOT NULL
      ORDER BY COALESCE(t.deleted_at, a.deleted_at) DESC
    ''');
    final mirror = await _readDeletionMirror();

    final List<ApiConfig> results = [];
    final seen = <String>{};
    for (final map in maps) {
      final id = map['id'] as String?;
      try {
        final effective =
            mirror[id] ?? (map['effective_deleted_at'] as String?);
        if (effective == null) continue;
        if (!seen.add(id!)) continue;
        final row = Map<String, Object?>.from(map);
        row['deleted_at'] = effective;
        results.add(_mapToApiConfig(row));
      } catch (e) {
        debugPrint('跳过损坏的API记录 id=$id: $e');
      }
    }
    // 镜像里有但 DB JOIN 没命中的（行被外部整体清除的情况极罕见，忽略）。
    return results;
  }

  /// 软删除：移入回收站，同时保留请求历史以便恢复。
  Future<void> softDeleteApiConfig(String id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'api_configs',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    // 墓碑是删除状态的权威记录：即便行被任何写入者覆盖也不会复活。
    await db.insert(
      'deleted_config_ids',
      {'id': id, 'deleted_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // prefs 镜像：DB 文件被外部覆盖（换机克隆/系统回滚）后的最后防线。
    await _mirrorSet(id, now);
  }

  /// 从回收站恢复。
  Future<void> restoreApiConfig(String id) async {
    final db = await database;
    await db.update(
      'api_configs',
      {
        'deleted_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete('deleted_config_ids', where: 'id = ?', whereArgs: [id]);
    await _mirrorRemove(id);
  }

  /// 彻底删除（连同请求历史）。返回是否确实删除了一行。
  Future<bool> purgeApiConfig(String id) async {
    final db = await database;
    await db.delete('deleted_config_ids', where: 'id = ?', whereArgs: [id]);
    await _mirrorRemove(id);
    await db
        .delete('request_history', where: 'api_config_id = ?', whereArgs: [id]);
    final count = await db
        .delete('api_configs', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  /// 清空回收站。返回清除的数量。
  Future<int> clearRecycleBin() async {
    final deleted = await getDeletedApiConfigs();
    if (deleted.isEmpty) return 0;
    final db = await database;
    final ids = deleted.map((c) => c.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.transaction((txn) async {
      await txn.delete('deleted_config_ids',
          where: 'id IN ($placeholders)', whereArgs: ids);
      await txn.delete('request_history',
          where: 'api_config_id IN ($placeholders)', whereArgs: ids);
      await txn.delete('api_configs',
          where: 'id IN ($placeholders)', whereArgs: ids);
    });
    return ids.length;
  }

  /// 清除超过保留期的回收站内容，返回清除的数量。在应用启动与打开回收站时调用。
  /// 两条批量 SQL + 事务：避免逐条删除留下半清状态。
  Future<int> purgeExpiredApiConfigs(DateTime cutoff) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT t.id AS id FROM deleted_config_ids t
        WHERE t.deleted_at < ?
      ''', [cutoff.toIso8601String()]);
      if (rows.isEmpty) return 0;
      final ids = rows.map((row) => row['id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await txn.delete('request_history',
          where: 'api_config_id IN ($placeholders)', whereArgs: ids);
      await txn.delete('api_configs',
          where: 'id IN ($placeholders)', whereArgs: ids);
      await txn.delete('deleted_config_ids',
          where: 'id IN ($placeholders)', whereArgs: ids);
      await _mirrorRemoveAll(ids);
      return ids.length;
    });
  }

  Future<ApiConfig?> findBusinessEquivalentApiConfig(
      ApiConfig candidate) async {
    // 包含回收站中的配置：同步进来的同款不应绕过本机删除决定。
    final configs = await getAllApiConfigs(includeDeleted: true);
    for (final config in configs) {
      if (ApiConfigIdentity.matches(config, candidate)) return config;
    }
    return null;
  }

  Future<void> updateApiConfig(ApiConfig api) async {
    final db = await database;
    final cipher = _cipher;
    await db.update(
      'api_configs',
      {
        'name': api.name,
        'base_url': api.baseUrl,
        'api_key': cipher == null ? api.apiKey : cipher.encrypt(api.apiKey),
        'models': api.models.join(','),
        'environment': api.environment,
        'api_group': api.group,
        'tags': api.tags.join(','),
        'is_favorite': api.isFavorite ? 1 : 0,
        'updated_at': api.updatedAt.toIso8601String(),
        'metadata': _encodeMetadata(api.metadata),
        'provider_id': api.providerId,
        'protocol_id': api.protocolId,
        'selected_model': api.selectedModel,
        'model_catalog_mode': api.modelCatalogMode,
        'model_source': api.modelSource,
        'models_refreshed_at': api.modelsRefreshedAt?.toIso8601String(),
        'import_source_name': api.importSourceName,
        'import_source_package': api.importSourcePackage,
        'import_trust_level': api.importTrustLevel,
        'expires_at': api.expiresAt?.toIso8601String(),
        'low_balance': api.lowBalanceThreshold,
        'monthly_budget': api.monthlyBudget,
      },
      where: 'id = ?',
      whereArgs: [api.id],
    );
  }

  Future<void> deleteApiConfig(String id) async {
    final db = await database;
    await db.delete('api_configs', where: 'id = ?', whereArgs: [id]);
    await db
        .delete('request_history', where: 'api_config_id = ?', whereArgs: [id]);
  }

  Future<BackupRestoreSummary> restoreBackup({
    required List<ApiConfig> configs,
    required List<Group> groups,
    required bool replaceExisting,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      if (replaceExisting) {
        await transaction.delete('request_history');
        await transaction.delete('api_configs');
        await transaction.delete('groups');
        // 用户显式选择"清空后恢复"：回收站一并清空（含墓碑）。
        await transaction.delete('deleted_config_ids');
      }
      for (final group in groups) {
        await transaction.insert(
          'groups',
          {
            'id': group.id,
            'name': group.name,
            'description': group.description,
            'color': group.color,
            'sort_order': group.sortOrder,
            'created_at': group.createdAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final config in configs) {
        // 合并模式不复活回收站中的同 id 配置：本机的删除决定优先。
        // 删除状态以墓碑表为权威（行标记可能被任何写入者覆盖）。
        if (!replaceExisting) {
          final tombstone = await transaction.query(
            'deleted_config_ids',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [config.id],
            limit: 1,
          );
          if (tombstone.isNotEmpty) {
            continue;
          }
          final existing = await transaction.query(
            'api_configs',
            columns: ['deleted_at'],
            where: 'id = ?',
            whereArgs: [config.id],
            limit: 1,
          );
          if (existing.isNotEmpty &&
              existing.first['deleted_at'] != null) {
            // 行上有标记但墓碑缺失（v9 迁移前的边角）：补录墓碑并跳过。
            await transaction.insert(
              'deleted_config_ids',
              {
                'id': config.id,
                'deleted_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            continue;
          }
        }
        await transaction.insert(
          'api_configs',
          _apiConfigToMap(config),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return BackupRestoreSummary(
      configsRestored: configs.length,
      groupsRestored: groups.length,
    );
  }

  ApiConfig _mapToApiConfig(Map<String, dynamic> map) {
    final modelsStr = map['models'] as String? ?? '';
    final models = modelsStr.isEmpty
        ? <String>[]
        : modelsStr.split(',').where((e) => e.trim().isNotEmpty).toList();

    final tagsStr = map['tags'] as String? ?? '';
    final tags = tagsStr.isEmpty
        ? <String>[]
        : tagsStr.split(',').where((e) => e.trim().isNotEmpty).toList();

    final createdAtStr = map['created_at'] as String?;
    final updatedAtStr = map['updated_at'] as String?;

    return ApiConfig(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      baseUrl: map['base_url'] as String? ?? '',
      apiKey: _decryptStoredApiKey(map['api_key'] as String? ?? ''),
      models: models,
      environment: map['environment'] as String? ?? 'development',
      group: map['api_group'] as String?,
      tags: tags,
      isFavorite: (map['is_favorite'] as int?) == 1,
      createdAt: createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: updatedAtStr != null
          ? DateTime.tryParse(updatedAtStr) ?? DateTime.now()
          : DateTime.now(),
      metadata: _decodeMetadata(map['metadata']),
      providerId: map['provider_id'] as String? ?? 'custom',
      protocolId: map['protocol_id'] as String? ?? 'openai_compatible',
      selectedModel: map['selected_model'] as String?,
      modelCatalogMode: map['model_catalog_mode'] as String? ?? 'saved',
      modelSource: map['model_source'] as String? ?? 'manual',
      modelsRefreshedAt: _parseDateTime(map['models_refreshed_at']),
      importSourceName: map['import_source_name'] as String?,
      importSourcePackage: map['import_source_package'] as String?,
      importTrustLevel: map['import_trust_level'] as String?,
      deletedAt: _parseDateTime(map['deleted_at']),
      expiresAt: _parseDateTime(map['expires_at']),
      lowBalanceThreshold: map['low_balance'] as String?,
      monthlyBudget: (map['monthly_budget'] as num?)?.toDouble(),
    );
  }

  /// 读出的 api_key 兼容三种形态：明文（未启用加密的历史数据）、
  /// `enc1:` 密文、以及主密钥丢失后解密失败的原样密文。
  /// 密文无法解密时返回空串——密文绝不能被当作真实 Key 外发。
  String _decryptStoredApiKey(String stored) {
    final cipher = _cipher;
    if (cipher == null) {
      return stored.startsWith(ApiKeyCipher.prefix) ? '' : stored;
    }
    return cipher.decrypt(stored);
  }

  String? _encodeMetadata(Map<String, dynamic>? metadata) =>
      metadata == null ? null : jsonEncode(metadata);

  Map<String, dynamic>? _decodeMetadata(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {
      // Preserve metadata written by pre-v2 builds, which used Map.toString().
    }
    return <String, dynamic>{'legacyRawMetadata': value};
  }

  DateTime? _parseDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  // ==================== Group operations ====================
  Future<bool> isGroupNameAvailable(
    String name, {
    String? excludingId,
  }) async {
    final db = await database;
    return _isGroupNameAvailable(db, name, excludingId: excludingId);
  }

  Future<bool> _isGroupNameAvailable(
    DatabaseExecutor executor,
    String name, {
    String? excludingId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;
    final matches = await executor.query(
      'groups',
      columns: const ['id'],
      where: excludingId == null
          ? 'LOWER(name) = LOWER(?)'
          : 'LOWER(name) = LOWER(?) AND id != ?',
      whereArgs: excludingId == null
          ? [normalizedName]
          : [normalizedName, excludingId],
      limit: 1,
    );
    return matches.isEmpty;
  }

  Future<void> _ensureGroupNameAvailable(
    DatabaseExecutor executor,
    String name, {
    String? excludingId,
  }) async {
    final isAvailable = await _isGroupNameAvailable(
      executor,
      name,
      excludingId: excludingId,
    );
    if (!isAvailable) {
      throw StateError('分组名称不能为空或已存在');
    }
  }

  Future<void> insertGroup(Group group) async {
    final db = await database;
    await db.transaction((transaction) async {
      await _ensureGroupNameAvailable(
        transaction,
        group.name,
        excludingId: group.id,
      );
      await transaction.insert(
        'groups',
        {
          'id': group.id,
          'name': group.name.trim(),
          'description': group.description,
          'color': group.color,
          'sort_order': group.sortOrder,
          'created_at': group.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Group?> getGroup(String id) async {
    final db = await database;
    final maps = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return _mapToGroup(maps.first);
  }

  Future<List<Group>> getAllGroups() async {
    final db = await database;
    final maps = await db.query('groups', orderBy: 'sort_order ASC');
    return maps.map((map) => _mapToGroup(map)).toList();
  }

  Future<void> updateGroup(Group group) async {
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'groups',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [group.id],
        limit: 1,
      );
      final previousName =
          existing.isEmpty ? null : existing.first['name'] as String?;
      if (previousName == null) {
        throw StateError('分组不存在');
      }
      await _ensureGroupNameAvailable(
        transaction,
        group.name,
        excludingId: group.id,
      );
      await transaction.update(
        'groups',
        {
          'name': group.name.trim(),
          'description': group.description,
          'color': group.color,
          'sort_order': group.sortOrder,
        },
        where: 'id = ?',
        whereArgs: [group.id],
      );
      if (previousName != group.name.trim()) {
        await transaction.update(
          'api_configs',
          {
            'api_group': group.name.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'api_group = ?',
          whereArgs: [previousName],
        );
      }
    });
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'groups',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final name = existing.isEmpty ? null : existing.first['name'] as String?;
      if (name != null) {
        await transaction.update(
          'api_configs',
          {
            'api_group': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'api_group = ?',
          whereArgs: [name],
        );
      }
      await transaction.delete('groups', where: 'id = ?', whereArgs: [id]);
    });
  }

  Group _mapToGroup(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // ==================== Request History operations ====================
  static const int _maxHistoryRows = 500;
  static const int _maxStoredResponseBytes = 256 * 1024;

  Future<void> insertRequestHistory(RequestHistory history) async {
    final db = await database;
    String? responseBody;
    if (history.responseBody != null) {
      responseBody = jsonEncode(history.responseBody);
      if (responseBody.length > _maxStoredResponseBytes) {
        // LLM 响应可达数百 KB，超限时只保留占位信息，避免数据库无限膨胀。
        responseBody = jsonEncode({
          '_note': '响应内容过大，未保存完整响应',
          '_originalBytes': responseBody.length,
        });
      }
    }
    await db.insert(
        'request_history',
        {
          'id': history.id,
          'api_config_id': history.apiConfigId,
          'model': history.model,
          'endpoint': history.endpoint,
          'request_body': jsonEncode(history.requestBody),
          'response_body': responseBody,
          'status_code': history.statusCode,
          'duration': history.duration,
          'prompt_tokens': history.promptTokens,
          'completion_tokens': history.completionTokens,
          'total_tokens': history.totalTokens,
          'cached_tokens': history.cachedTokens,
          'reasoning_tokens': history.reasoningTokens,
          'created_at': history.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    // 保留窗口写法：索引覆盖 created_at，代价远低于 NOT IN 子查询。
    await db.execute(
      'DELETE FROM request_history WHERE created_at < ('
      'SELECT created_at FROM request_history '
      'ORDER BY created_at DESC LIMIT 1 OFFSET ?'
      ')',
      [_maxHistoryRows - 1],
    );
  }

  Future<List<RequestHistory>> getRequestHistory(
      {String? apiConfigId, int limit = 50}) async {
    try {
      final db = await database;
      final maps = await db.query(
        'request_history',
        where: apiConfigId != null ? 'api_config_id = ?' : null,
        whereArgs: apiConfigId != null ? [apiConfigId] : null,
        orderBy: 'created_at DESC',
        limit: limit,
      );

      final List<RequestHistory> results = [];
      for (final map in maps) {
        try {
          results.add(_mapToRequestHistory(map));
        } catch (e) {
          debugPrint('跳过损坏的历史记录: $e');
        }
      }
      return results;
    } catch (e) {
      debugPrint('getRequestHistory 错误: $e');
      return [];
    }
  }

  RequestHistory _mapToRequestHistory(Map<String, dynamic> map) {
    Map<String, dynamic> requestBody = {};
    try {
      final bodyStr = map['request_body'] as String? ?? '{}';
      requestBody = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {}

    Map<String, dynamic>? responseBody;
    try {
      final respStr = map['response_body'] as String?;
      if (respStr != null && respStr.isNotEmpty) {
        responseBody = jsonDecode(respStr) as Map<String, dynamic>;
      }
    } catch (_) {}

    final createdAtStr = map['created_at'] as String?;

    return RequestHistory(
      id: map['id'] as String,
      apiConfigId: map['api_config_id'] as String,
      model: map['model'] as String,
      endpoint: map['endpoint'] as String,
      requestBody: requestBody,
      responseBody: responseBody,
      statusCode: map['status_code'] as int?,
      duration: map['duration'] as int?,
      promptTokens: map['prompt_tokens'] as int?,
      completionTokens: map['completion_tokens'] as int?,
      totalTokens: map['total_tokens'] as int?,
      cachedTokens: map['cached_tokens'] as int?,
      reasoningTokens: map['reasoning_tokens'] as int?,
      createdAt: createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Future<void> deleteRequestHistory(String id) async {
    final db = await database;
    await db.delete('request_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearRequestHistory() async {
    final db = await database;
    await db.delete('request_history');
  }

  /// 用量聚合行（SQL 下推：不读 body，历史再多也恒定开销）。
  Future<List<Map<String, Object?>>> getUsageSummary() async {
    final db = await database;
    return db.rawQuery('''
      SELECT api_config_id,
             COUNT(*) AS request_count,
             SUM(CASE WHEN status_code >= 200 AND status_code < 300
                 THEN 1 ELSE 0 END) AS success_count,
             SUM(COALESCE(prompt_tokens, 0)) AS prompt_tokens,
             SUM(COALESCE(completion_tokens, 0)) AS completion_tokens,
             SUM(COALESCE(total_tokens, 0)) AS total_tokens,
             MAX(created_at) AS last_used_at
      FROM request_history
      GROUP BY api_config_id
      ORDER BY total_tokens DESC
    ''');
  }

  // ==================== Third-party interoperability audits ====================
  Future<void> insertInteropAudit(ApiInteropAudit audit) async {
    final db = await database;
    await db.insert(
      'api_interop_audits',
      audit.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ApiInteropAudit>> getInteropAudits({int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'api_interop_audits',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps
        .map((map) => ApiInteropAudit.fromDatabaseMap(map))
        .toList(growable: false);
  }

  Future<void> clearInteropAudits() async {
    final db = await database;
    await db.delete('api_interop_audits');
  }
}
