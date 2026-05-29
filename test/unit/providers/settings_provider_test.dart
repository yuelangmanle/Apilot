import 'package:flutter_test/flutter_test.dart';
import 'package:api_manager/features/settings/providers/settings_provider.dart';

void main() {
  group('SettingsProvider', () {
    late SettingsProvider provider;

    setUp(() {
      provider = SettingsProvider();
    });

    test('should have dark mode disabled by default', () {
      expect(provider.isDarkMode, false);
    });

    test('should toggle dark mode', () {
      provider.toggleDarkMode();
      expect(provider.isDarkMode, true);
      provider.toggleDarkMode();
      expect(provider.isDarkMode, false);
    });

    test('should have auto discovery enabled by default', () {
      expect(provider.autoDiscovery, true);
    });

    test('should toggle auto discovery', () {
      provider.toggleAutoDiscovery();
      expect(provider.autoDiscovery, false);
    });

    test('should have bluetooth sync disabled by default', () {
      expect(provider.bluetoothSync, false);
    });

    test('should toggle bluetooth sync', () {
      provider.toggleBluetoothSync();
      expect(provider.bluetoothSync, true);
    });

    test('should notify listeners on dark mode toggle', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.toggleDarkMode();
      expect(notifyCount, 1);
    });
  });
}
