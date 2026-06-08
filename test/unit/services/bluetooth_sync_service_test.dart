import 'package:api_manager/features/sync/services/bluetooth_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('BluetoothSyncService Android permission plan', () {
    test('Android 12 and newer requests Nearby Devices Bluetooth permissions',
        () {
      final permissions = BluetoothSyncService.androidPermissionPlanForSdk(
        sdkInt: 33,
        includeAdvertise: true,
      );

      expect(permissions, contains(Permission.bluetoothScan));
      expect(permissions, contains(Permission.bluetoothConnect));
      expect(permissions, contains(Permission.bluetoothAdvertise));
      expect(permissions, isNot(contains(Permission.locationWhenInUse)));
    });

    test('Android 11 and older requests location for BLE discovery', () {
      final permissions = BluetoothSyncService.androidPermissionPlanForSdk(
        sdkInt: 30,
        includeAdvertise: true,
      );

      expect(permissions, contains(Permission.locationWhenInUse));
      expect(permissions, isNot(contains(Permission.bluetoothScan)));
    });
  });
}
