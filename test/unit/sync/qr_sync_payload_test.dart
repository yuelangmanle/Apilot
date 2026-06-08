import 'package:api_manager/features/sync/utils/qr_sync_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractSyncIp', () {
    test('reads the existing pipe-delimited QR payload', () {
      expect(
        extractSyncIp('192.168.1.23|device-id|MacBook'),
        '192.168.1.23',
      );
    });

    test('reads an HTTP URL QR payload', () {
      expect(
        extractSyncIp('http://192.168.1.23:45679/ping'),
        '192.168.1.23',
      );
    });

    test('reads a JSON QR payload from newer scanners', () {
      expect(
        extractSyncIp('{"ip":"10.0.0.8","name":"Phone"}'),
        '10.0.0.8',
      );
    });

    test('rejects invalid addresses', () {
      expect(extractSyncIp('999.168.1.23'), isNull);
      expect(extractSyncIp('not an ip'), isNull);
    });
  });
}
