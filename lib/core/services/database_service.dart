import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/api_config.dart';
import '../models/group.dart';
import '../models/request_history.dart';

class DatabaseService {
  Database? _database;
  bool _isInitialized = false;
  final String? _customDbPath;

  DatabaseService({String? dbPath}) : _customDbPath = dbPath;

  Future<Database> get database async {
    if (_database != null && _isInitialized) return _database!;
    _database = await _initializeDatabase();
    _isInitialized = true;
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbPath2 = _customDbPath ?? path.join(dbPath, 'api_manager.db');

    return await openDatabase(
      dbPath2,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_configs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        models TEXT NOT NULL,
        environment TEXT NOT NULL,
        api_group TEXT,
        tags TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        metadata TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS request_history (
        id TEXT PRIMARY KEY,
        api_config_id TEXT NOT NULL,
        model TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        request_body TEXT NOT NULL,
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
  }

  Future<void> initialize() async {
    await database;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
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
        'metadata': api.metadata?.toString(),
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
    final db = await database;
    final maps = await db.query('api_configs', orderBy: 'name ASC');

    return maps.map((map) => _mapToApiConfig(map)).toList();
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
        'metadata': api.metadata?.toString(),
      },
      where: 'id = ?',
      whereArgs: [api.id],
    );
  }

  Future<void> deleteApiConfig(String id) async {
    final db = await database;
    await db.delete(
      'api_configs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  ApiConfig _mapToApiConfig(Map<String, dynamic> map) {
    return ApiConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      baseUrl: map['base_url'] as String,
      apiKey: map['api_key'] as String,
      models: (map['models'] as String).split(','),
      environment: map['environment'] as String,
      group: map['api_group'] as String?,
      tags: (map['tags'] as String?)?.split(',') ?? [],
      isFavorite: (map['is_favorite'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
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
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Group?> getGroup(String id) async {
    final db = await database;
    final maps = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
    );

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
      whereArgs: [group.id],
    );
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    await db.delete(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
    );
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
        'request_body': history.requestBody.toString(),
        'response_body': history.responseBody?.toString(),
        'status_code': history.statusCode,
        'duration': history.duration,
        'created_at': history.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RequestHistory>> getRequestHistory({String? apiConfigId, int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'request_history',
      where: apiConfigId != null ? 'api_config_id = ?' : null,
      whereArgs: apiConfigId != null ? [apiConfigId] : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return maps.map((map) => RequestHistory(
      id: map['id'] as String,
      apiConfigId: map['api_config_id'] as String,
      model: map['model'] as String,
      endpoint: map['endpoint'] as String,
      requestBody: {},
      responseBody: map['response_body'] != null ? {} : null,
      statusCode: map['status_code'] as int?,
      duration: map['duration'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    )).toList();
  }

  Future<void> deleteRequestHistory(String id) async {
    final db = await database;
    await db.delete(
      'request_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRequestHistory() async {
    final db = await database;
    await db.delete('request_history');
  }
}
