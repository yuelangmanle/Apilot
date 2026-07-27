import 'dart:typed_data';

import 'package:api_manager/features/sync/services/bluetooth_transfer_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BluetoothTransferProtocol', () {
    test('restores a frame split across arbitrary BLE writes', () {
      final encoded = BluetoothTransferProtocol.encodeFrame(
        const BluetoothTransferFrame(
          type: BluetoothTransferFrameType.offer,
          sessionId: 'session-1',
          data: {'operation': 'push', 'count': 2},
        ),
      );
      final decoder = BluetoothFrameDecoder();

      expect(decoder.add(encoded.sublist(0, 3)), isEmpty);
      expect(decoder.add(encoded.sublist(3, 11)), isEmpty);
      final frames = decoder.add(encoded.sublist(11));

      expect(frames, hasLength(1));
      expect(frames.single.type, BluetoothTransferFrameType.offer);
      expect(frames.single.sessionId, 'session-1');
      expect(frames.single.data['count'], 2);
    });

    test('creates a checked payload stream and restores the original bytes',
        () {
      final payload = Uint8List.fromList(
        List<int>.generate(751, (index) => index % 251),
      );
      final frames = BluetoothTransferProtocol.createPayloadFrames(
        sessionId: 'session-2',
        payload: payload,
        chunkSize: 96,
      );
      final assembler = BluetoothPayloadAssembler(sessionId: 'session-2');

      for (final frame in frames) {
        assembler.add(frame);
      }

      expect(assembler.isComplete, isTrue);
      expect(assembler.build(), payload);
    });

    test('rejects payload chunks that arrive out of order', () {
      final frames = BluetoothTransferProtocol.createPayloadFrames(
        sessionId: 'session-3',
        payload: Uint8List.fromList(List<int>.filled(250, 7)),
        chunkSize: 96,
      );
      final assembler = BluetoothPayloadAssembler(sessionId: 'session-3');

      expect(() => assembler.add(frames[1]), throwsFormatException);
    });

    test('rejects a completed payload whose checksum does not match', () {
      final frames = BluetoothTransferProtocol.createPayloadFrames(
        sessionId: 'session-4',
        payload: Uint8List.fromList(List<int>.filled(80, 9)),
        chunkSize: 96,
      );
      final tampered = frames.single.copyWith(
        data: {
          ...frames.single.data,
          'checksum': 'not-the-real-checksum',
        },
      );
      final assembler = BluetoothPayloadAssembler(sessionId: 'session-4');
      assembler.add(tampered);

      expect(() => assembler.build(), throwsFormatException);
    });
  });
}
