import 'package:api_manager/core/models/device_info.dart';
import 'package:api_manager/features/sync/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SyncService device discovery', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('keeps a stable local device id across calls', () async {
      final service = SyncService();

      final first = await service.getLocalDeviceInfo();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await service.getLocalDeviceInfo();

      expect(second.id, first.id);
    });

    test('dedupes discovered devices by IP when sender id changes', () async {
      final service = SyncService(localDeviceIdOverride: 'local-device');

      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'remote-1',
          name: 'Phone',
          platform: 'android',
          ipAddress: '192.168.1.23',
        ),
      );
      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'remote-2',
          name: 'Phone',
          platform: 'android',
          ipAddress: '192.168.1.23',
        ),
      );

      expect(service.discoveredDevices, hasLength(1));
      expect(service.discoveredDevices.single.id, 'remote-2');
    });

    test('dedupes discovered devices by stable device id when IP changes',
        () async {
      final service = SyncService(localDeviceIdOverride: 'local-device');

      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'remote-1',
          name: 'Phone',
          platform: 'android',
          ipAddress: '192.168.1.23',
        ),
      );
      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'remote-1',
          name: 'Phone',
          platform: 'android',
          ipAddress: '192.168.1.24',
        ),
      );

      expect(service.discoveredDevices, hasLength(1));
      expect(service.discoveredDevices.single.ipAddress, '192.168.1.24');
    });

    test('clears WiFi-discovered devices when discovery is disabled', () async {
      final service = SyncService(localDeviceIdOverride: 'local-device');

      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'remote-1',
          name: 'Phone',
          platform: 'android',
          ipAddress: '192.168.1.23',
        ),
      );

      await service.setDiscoveryEnabled(false, clearDevices: true);

      expect(service.discoveredDevices, isEmpty);
      expect(service.isDiscoveryRunning, isFalse);
    });

    test('ignores discovered records from the local device id', () async {
      final service = SyncService(localDeviceIdOverride: 'local-device');

      await service.upsertDiscoveredDevice(
        DeviceInfo(
          id: 'local-device',
          name: 'My Mac',
          platform: 'macos',
          ipAddress: '192.168.1.10',
        ),
      );

      expect(service.discoveredDevices, isEmpty);
    });
  });
}
