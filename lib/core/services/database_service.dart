import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/api_config.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initializeDatabase();
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbPath2 = path.join(dbPath, 'api_manager.db');

    return await openDatabase(
      dbPath2,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE api_configs (
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
      CREATE TABLE request_history (
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
      CREATE TABLE groups (
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
    final db = await database;
    await db.close();
    _database = null;
  }

  // API Config operations
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

    final map = maps.first;
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

  Future<List<ApiConfig>> getAllApiConfigs() async {
    final db = await database;
    final maps = await db.query('api_configs', orderBy: 'name ASC');

    return maps.map((map) => ApiConfig(
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
    )).toList();
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
}
