import 'package:flutter/foundation.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/database_service.dart';

class ApiProvider with ChangeNotifier {
  final DatabaseService _databaseService;
  List<ApiConfig> _apiConfigs = [];
  String? _selectedGroup;
  String _searchQuery = '';
  String? _error;
  bool _showFavoritesOnly = false;

  ApiProvider(this._databaseService);

  String? get error => _error;
  bool get showFavoritesOnly => _showFavoritesOnly;
  String? get selectedGroup => _selectedGroup;

  List<ApiConfig> get apiConfigs {
    var configs = _apiConfigs;

    if (_showFavoritesOnly) {
      configs = configs.where((c) => c.isFavorite).toList();
    }

    if (_selectedGroup != null) {
      configs = configs.where((c) => c.group == _selectedGroup).toList();
    }

    if (_searchQuery.isNotEmpty) {
      configs = configs.where((c) =>
        c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c.baseUrl.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    return configs;
  }

  List<String> get availableGroups {
    final groups = _apiConfigs
        .where((c) => c.group != null && c.group!.isNotEmpty)
        .map((c) => c.group!)
        .toSet()
        .toList();
    groups.sort();
    return groups;
  }

  Future<void> loadApiConfigs() async {
    try {
      _apiConfigs = await _databaseService.getAllApiConfigs();
      _error = null;
    } catch (e) {
      debugPrint('loadApiConfigs 错误: $e');
      _error = '加载失败: $e';
    }
    notifyListeners();
  }

  Future<void> addApiConfig(ApiConfig api) async {
    try {
      await _databaseService.insertApiConfig(api);
      final saved = await _databaseService.getApiConfig(api.id);
      if (saved != null) {
        _apiConfigs = await _databaseService.getAllApiConfigs();
        _error = null;
      } else {
        _error = '保存失败：数据未写入';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('addApiConfig 错误: $e');
      _error = '保存失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateApiConfig(ApiConfig api) async {
    try {
      await _databaseService.updateApiConfig(api);
      final index = _apiConfigs.indexWhere((a) => a.id == api.id);
      if (index != -1) {
        _apiConfigs[index] = api;
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('updateApiConfig 错误: $e');
      _error = '更新失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteApiConfig(String id) async {
    try {
      await _databaseService.deleteApiConfig(id);
      _apiConfigs.removeWhere((a) => a.id == id);
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('deleteApiConfig 错误: $e');
      _error = '删除失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  void setSelectedGroup(String? group) {
    _selectedGroup = group;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleFavoritesOnly() {
    _showFavoritesOnly = !_showFavoritesOnly;
    notifyListeners();
  }

  List<ApiConfig> getFavorites() {
    return _apiConfigs.where((c) => c.isFavorite).toList();
  }
}
