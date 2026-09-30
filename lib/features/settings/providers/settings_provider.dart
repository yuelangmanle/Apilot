import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ApilotThemeMode { system, light, dark }

class SettingsProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool _autoDiscovery = true;
  bool _bluetoothSync = false;
  ApilotThemeMode _themeMode = ApilotThemeMode.system;

  bool get isDarkMode => _isDarkMode;
  bool get autoDiscovery => _autoDiscovery;
  bool get bluetoothSync => _bluetoothSync;
  ApilotThemeMode get themeMode => _themeMode;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _autoDiscovery = prefs.getBool('autoDiscovery') ?? true;
      _bluetoothSync = prefs.getBool('bluetoothSync') ?? false;
      final mode = prefs.getString('themeMode') ?? 'system';
      _themeMode = ApilotThemeMode.values
          .firstWhere((m) => m.name == mode, orElse: () => ApilotThemeMode.system);
      notifyListeners();
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  /// 主题三态：跟随系统 / 亮色 / 暗色。
  Future<void> setThemeMode(ApilotThemeMode mode) async {
    _themeMode = mode;
    _isDarkMode = mode == ApilotThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
    await _saveSetting('isDarkMode', _isDarkMode);
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    _themeMode =
        _isDarkMode ? ApilotThemeMode.dark : ApilotThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeMode.name);
    await _saveSetting('isDarkMode', _isDarkMode);
  }

  Future<void> toggleAutoDiscovery() async {
    _autoDiscovery = !_autoDiscovery;
    notifyListeners();
    await _saveSetting('autoDiscovery', _autoDiscovery);
  }

  Future<void> toggleBluetoothSync() async {
    _bluetoothSync = !_bluetoothSync;
    notifyListeners();
    await _saveSetting('bluetoothSync', _bluetoothSync);
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }
}
