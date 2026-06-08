import 'package:api_manager/features/sync/utils/sync_mode_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncModePolicy', () {
    test('Bluetooth mode does not run WiFi discovery automatically', () {
      expect(
          SyncModePolicy.shouldRunWifiDiscovery(SyncMode.bluetooth), isFalse);
      expect(SyncModePolicy.shouldRunWifiDiscovery(SyncMode.wifi), isTrue);
    });

    test('Bluetooth empty copy does not mention WiFi or hotspot', () {
      final message = SyncModePolicy.emptyStateMessage(SyncMode.bluetooth);

      expect(message, isNot(contains('WiFi')));
      expect(message, isNot(contains('热点')));
      expect(message, contains('蓝牙'));
    });

    test('Bluetooth no-device status does not fall back to WiFi wording', () {
      final message = SyncModePolicy.bluetoothDiscoveryStatus(
        discovered: 0,
        added: 0,
      );

      expect(message, isNot(contains('WiFi')));
      expect(message, isNot(contains('扫码')));
      expect(message, contains('蓝牙未发现设备'));
    });
  });
}
