import 'package:flutter/foundation.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/database_service.dart';

class HistoryProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  List<RequestHistory> _history = [];
  bool _loaded = false;

  List<RequestHistory> get history => List.unmodifiable(_history);

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      _history = await _databaseService.getRequestHistory(limit: 200);
      _loaded = true;
    }
  }

  Future<void> loadHistory() async {
    _history = await _databaseService.getRequestHistory(limit: 200);
    _loaded = true;
    notifyListeners();
  }

  Future<void> addHistory(RequestHistory item) async {
    await _ensureLoaded();
    await _databaseService.insertRequestHistory(item);
    _history.insert(0, item);
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
