import 'package:flutter/foundation.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/database_service.dart';

class ApiProvider with ChangeNotifier {
  final DatabaseService _databaseService;
  List<ApiConfig> _apiConfigs = [];
  String? _selectedGroup;
  String _searchQuery = '';

  ApiProvider(this._databaseService);

  List<ApiConfig> get apiConfigs {
    var configs = _apiConfigs;

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

  Future<void> loadApiConfigs() async {
    _apiConfigs = await _databaseService.getAllApiConfigs();
    notifyListeners();
  }

  Future<void> addApiConfig(ApiConfig api) async {
    await _databaseService.insertApiConfig(api);
    _apiConfigs.add(api);
    notifyListeners();
  }

  Future<void> updateApiConfig(ApiConfig api) async {
    await _databaseService.updateApiConfig(api);
    final index = _apiConfigs.indexWhere((a) => a.id == api.id);
    if (index != -1) {
      _apiConfigs[index] = api;
      notifyListeners();
    }
  }

  Future<void> deleteApiConfig(String id) async {
    await _databaseService.deleteApiConfig(id);
    _apiConfigs.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void setSelectedGroup(String? group) {
    _selectedGroup = group;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  List<ApiConfig> getFavorites() {
    return _apiConfigs.where((c) => c.isFavorite).toList();
  }
}
