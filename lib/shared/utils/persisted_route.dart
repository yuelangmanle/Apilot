import 'package:shared_preferences/shared_preferences.dart';

/// 二级页面路由持久化：记录最后停留的二级页面描述符，
/// 应用重启（进程被杀导致 Navigator 栈丢失）后由 AppShell 重建。
class PersistedRoute {
  PersistedRoute._();

  static const _key = 'apilot_last_route';
  static const _argKey = 'apilot_last_route_arg';

  static Future<void> save(String routeKey, [String? arg]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, routeKey);
      await prefs.setString(_argKey, arg ?? '');
    } catch (_) {}
  }

  static Future<MapEntry<String, String?>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final route = prefs.getString(_key);
      if (route == null || route.isEmpty) return null;
      final arg = prefs.getString(_argKey);
      return MapEntry(route, arg!.isEmpty ? null : arg);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_argKey);
    } catch (_) {}
  }

  /// 仅当当前记录的正是该路由时清除（避免误清上层压入的新标记）。
  static Future<void> clearIfCurrent(String routeKey) async {
    final current = await load();
    if (current != null && current.key == routeKey) {
      await clear();
    }
  }
}
