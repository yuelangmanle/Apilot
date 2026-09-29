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

  group('extractSyncKey', () {
    test('reads the pairing key segment from new QR payloads', () {
      expect(
        extractSyncKey('192.168.1.23|device-id|MacBook|k=AbC123-_xyz'),
        'AbC123-_xyz',
      );
    });

    test('returns null for legacy payloads without a key segment', () {
      expect(extractSyncKey('192.168.1.23|device-id|MacBook'), isNull);
      expect(extractSyncKey('http://192.168.1.23:45679/ping'), isNull);
      expect(extractSyncKey(''), isNull);
    });

    test('extractSyncIp still works with a key segment appended', () {
      expect(
        extractSyncIp('192.168.1.23|device-id|MacBook|k=AbC123'),
        '192.168.1.23',
      );
    });
  });
}
