import 'package:flutter/foundation.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/database_service.dart';

class HistoryProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  List<RequestHistory> _history = [];
  bool _loaded = false;
  final Map<String, String> _apiNames = {};

  List<RequestHistory> get history => List.unmodifiable(_history);

  /// id → API 名称的映射，随历史一起加载；列表行直接同步取值，
  /// 避免每行一次数据库查询。
  Map<String, String> get apiNames => Map.unmodifiable(_apiNames);

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      await loadHistory();
    }
  }

  Future<void> loadHistory() async {
    // 与数据库 500 条上限对齐：统计口径与文案一致。
    _history = await _databaseService.getRequestHistory(limit: 500);
    _loaded = true;
    try {
      final configs = await _databaseService.getAllApiConfigs();
      _apiNames
        ..clear()
        ..addEntries(configs.map((c) => MapEntry(c.id, c.name)));
    } catch (_) {
      // 名称映射失败不影响历史展示，只是行内少显示一个前缀。
    }
    notifyListeners();
  }

  Future<void> addHistory(RequestHistory item) async {
    await _ensureLoaded();
    await _databaseService.insertRequestHistory(item);
    _history.insert(0, item);
    if (!_apiNames.containsKey(item.apiConfigId)) {
      try {
        final config = await _databaseService.getApiConfig(item.apiConfigId);
        if (config != null) _apiNames[config.id] = config.name;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _databaseService.clearRequestHistory();
    _history.clear();
    notifyListeners();
  }

  Future<void> deleteHistoryItem(String id) async {
    await _databaseService.deleteRequestHistory(id);
    _history.removeWhere((h) => h.id == id);
    notifyListeners();
  }

  List<RequestHistory> getHistoryByApi(String apiConfigId) {
    return _history.where((h) => h.apiConfigId == apiConfigId).toList();
  }
}
