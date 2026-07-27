import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import '../models/api_config.dart';
import '../models/api_interop_audit.dart';
import '../models/group.dart';
import '../models/request_history.dart';

class DatabaseService {
  static Database? _database;
  static int _refCount = 0;
  final String? _customDbPath;

  DatabaseService({String? dbPath}) : _customDbPath = dbPath;

  Future<Database> get database async {
    if (_database != null) {
      _refCount++;
      return _database!;
    }
    _database = await _initializeDatabase();
    _refCount = 1;
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbPath2 = _customDbPath ?? path.join(dbPath, 'api_manager.db');

    return await openDatabase(
      dbPath2,
      version: 3,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
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
        import_trust_level TEXT
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
        created_at TEXT NOT NULL,
        FOREIGN KEY (api_config_id) REFERENCES api_configs (id)
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

  Future<void> close() async {
    if (_refCount > 0) {
      _refCount--;
    }
    if (_refCount == 0 && _database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> forceClose() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _refCount = 0;
    }
  }

  // ==================== API Config operations ====================
  Future<void> insertApiConfig(ApiConfig api) async {
    final db = await database;
    await db.insert(
      'api_configs',
      {
        'id': api.id,
        'name': api.name,
        'base_url': api.baseUrl,
        'api_key': api.apiKey,
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<List<ApiConfig>> getAllApiConfigs() async {
    try {
      final db = await database;
      final maps = await db.query('api_configs', orderBy: 'name ASC');

      final List<ApiConfig> results = [];
      for (final map in maps) {
        try {
          results.add(_mapToApiConfig(map));
        } catch (e) {
          debugPrint('跳过损坏的API记录 id=${map['id']}: $e');
        }
      }
      return results;
    } catch (e) {
      debugPrint('getAllApiConfigs 错误: $e');
      return [];
    }
  }

  Future<void> updateApiConfig(ApiConfig api) async {
    final db = await database;
    await db.update(
      'api_configs',
      {
        'name': api.name,
        'base_url': api.baseUrl,
        'api_key': api.apiKey,
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
      apiKey: map['api_key'] as String? ?? '',
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
    );
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
  Future<void> insertGroup(Group group) async {
    final db = await database;
    await db.insert(
        'groups',
        {
          'id': group.id,
          'name': group.name,
          'description': group.description,
          'color': group.color,
          'sort_order': group.sortOrder,
          'created_at': group.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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
    await db.update(
        'groups',
        {
          'name': group.name,
          'description': group.description,
          'color': group.color,
          'sort_order': group.sortOrder,
        },
        where: 'id = ?',
        whereArgs: [group.id]);
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
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
  Future<void> insertRequestHistory(RequestHistory history) async {
    final db = await database;
    await db.insert(
        'request_history',
        {
          'id': history.id,
          'api_config_id': history.apiConfigId,
          'model': history.model,
          'endpoint': history.endpoint,
          'request_body': jsonEncode(history.requestBody),
          'response_body': history.responseBody != null
              ? jsonEncode(history.responseBody)
              : null,
          'status_code': history.statusCode,
          'duration': history.duration,
          'created_at': history.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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
