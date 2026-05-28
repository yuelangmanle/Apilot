import 'package:flutter/foundation.dart';
import '../../../core/models/request_history.dart';

class HistoryProvider with ChangeNotifier {
  final List<RequestHistory> _history = [];

  List<RequestHistory> get history => List.unmodifiable(_history);

  void addHistory(RequestHistory item) {
    _history.insert(0, item);
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  List<RequestHistory> getHistoryByApi(String apiConfigId) {
    return _history.where((h) => h.apiConfigId == apiConfigId).toList();
  }
}
