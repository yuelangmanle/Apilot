import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool _autoDiscovery = true;
  bool _bluetoothSync = false;

  bool get isDarkMode => _isDarkMode;
  bool get autoDiscovery => _autoDiscovery;
  bool get bluetoothSync => _bluetoothSync;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _autoDiscovery = prefs.getBool('autoDiscovery') ?? true;
      _bluetoothSync = prefs.getBool('bluetoothSync') ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
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
