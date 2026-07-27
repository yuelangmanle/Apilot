import 'package:api_manager/features/sync/services/qr_scanner_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrScannerError', () {
    test('maps a temporary camera permission denial to a retry action', () {
      final error = QrScannerError.fromPlatformCode('camera_permission_denied');

      expect(error.message, '需要相机权限才能扫描二维码');
      expect(error.canRetry, isTrue);
      expect(error.canOpenSettings, isFalse);
    });

    test('maps a permanent camera permission denial to settings', () {
      final error = QrScannerError.fromPlatformCode(
        'camera_permission_permanently_denied',
      );

      expect(error.message, '相机权限已被系统拒绝，请在系统设置中允许 Apilot 使用相机');
      expect(error.canRetry, isFalse);
      expect(error.canOpenSettings, isTrue);
    });
  });
}
