import 'package:flutter/foundation.dart';

class SettingsProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool _autoDiscovery = true;
  bool _bluetoothSync = false;

  bool get isDarkMode => _isDarkMode;
  bool get autoDiscovery => _autoDiscovery;
  bool get bluetoothSync => _bluetoothSync;

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void toggleAutoDiscovery() {
    _autoDiscovery = !_autoDiscovery;
    notifyListeners();
  }

  void toggleBluetoothSync() {
    _bluetoothSync = !_bluetoothSync;
    notifyListeners();
  }
}
