import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum BluetoothTransferFrameType {
  offer,
  accepted,
  rejected,
  payload,
  complete,
  result,
  error,
}

extension on BluetoothTransferFrameType {
  String get wireName => name;
}

BluetoothTransferFrameType _parseFrameType(String value) {
  return BluetoothTransferFrameType.values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw FormatException('未知蓝牙传输帧类型：$value'),
  );
}

class BluetoothTransferFrame {
  static const protocolVersion = 1;

  final BluetoothTransferFrameType type;
  final String sessionId;
  final Map<String, dynamic> data;

  const BluetoothTransferFrame({
    required this.type,
    required this.sessionId,
    this.data = const {},
  });

  BluetoothTransferFrame copyWith({
    BluetoothTransferFrameType? type,
    String? sessionId,
    Map<String, dynamic>? data,
  }) {
    return BluetoothTransferFrame(
      type: type ?? this.type,
      sessionId: sessionId ?? this.sessionId,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': protocolVersion,
        'type': type.wireName,
        'sessionId': sessionId,
        'data': data,
      };

  factory BluetoothTransferFrame.fromJson(Map<String, dynamic> json) {
    if (json['version'] != protocolVersion) {
      throw const FormatException('不支持的蓝牙传输协议版本');
    }
    final sessionId = json['sessionId'];
    final type = json['type'];
    if (sessionId is! String || sessionId.isEmpty || type is! String) {
      throw const FormatException('蓝牙传输帧缺少会话标识或类型');
    }
    final rawData = json['data'];
    if (rawData != null && rawData is! Map) {
      throw const FormatException('蓝牙传输帧数据格式错误');
    }
    return BluetoothTransferFrame(
      type: _parseFrameType(type),
      sessionId: sessionId,
      data: rawData == null
          ? const {}
          : Map<String, dynamic>.from(rawData as Map),
    );
  }
}

/// Framing used above BLE writes/notifications. BLE can split a write at any
/// MTU boundary, so each JSON frame is prefixed with a four-byte length.
class BluetoothTransferProtocol {
  static const maxFrameBytes = 64 * 1024;
  static const maxTransferBytes = 1024 * 1024;

  static Uint8List encodeFrame(BluetoothTransferFrame frame) {
    final data = Uint8List.fromList(utf8.encode(jsonEncode(frame.toJson())));
    if (data.length > maxFrameBytes) {
      throw ArgumentError.value(data.length, 'frame', '蓝牙帧超过最大长度');
    }
    final output = Uint8List(data.length + 4);
    final view = ByteData.sublistView(output);
    view.setUint32(0, data.length, Endian.big);
    output.setRange(4, output.length, data);
    return output;
  }

  static List<BluetoothTransferFrame> createPayloadFrames({
    required String sessionId,
    required Uint8List payload,
    int chunkSize = 120,
  }) {
    if (payload.length > maxTransferBytes) {
      throw ArgumentError.value(payload.length, 'payload', '蓝牙传输内容超过 1 MiB');
    }
    if (chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', '分块长度必须大于零');
    }

    final total =
        payload.isEmpty ? 1 : (payload.length + chunkSize - 1) ~/ chunkSize;
    final checksum = sha256.convert(payload).toString();
    return List.generate(total, (index) {
      final start = index * chunkSize;
      final end =
          payload.isEmpty ? 0 : (start + chunkSize).clamp(0, payload.length);
      final chunk = payload.sublist(start, end);
      return BluetoothTransferFrame(
        type: BluetoothTransferFrameType.payload,
        sessionId: sessionId,
        data: {
          'index': index,
          'total': total,
          'checksum': checksum,
          'content': base64Encode(chunk),
        },
      );
    });
  }
}

class BluetoothFrameDecoder {
  final List<int> _pending = [];

  List<BluetoothTransferFrame> add(Uint8List bytes) {
    _pending.addAll(bytes);
    final frames = <BluetoothTransferFrame>[];
    while (_pending.length >= 4) {
      final length = ByteData.sublistView(Uint8List.fromList(_pending), 0, 4)
          .getUint32(0, Endian.big);
      if (length < 1 || length > BluetoothTransferProtocol.maxFrameBytes) {
        _pending.clear();
        throw FormatException('蓝牙传输帧长度无效：$length');
      }
      if (_pending.length < length + 4) break;
      final jsonBytes = _pending.sublist(4, length + 4);
      _pending.removeRange(0, length + 4);
      final decoded = jsonDecode(utf8.decode(jsonBytes));
      if (decoded is! Map) throw const FormatException('蓝牙传输帧不是对象');
      frames.add(BluetoothTransferFrame.fromJson(
        Map<String, dynamic>.from(decoded),
      ));
    }
    return frames;
  }
}

class BluetoothPayloadAssembler {
  final String sessionId;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _nextIndex = 0;
  int? _total;
  String? _checksum;

  BluetoothPayloadAssembler({required this.sessionId});

  bool get isComplete => _total != null && _nextIndex == _total;

  void add(BluetoothTransferFrame frame) {
    if (frame.type != BluetoothTransferFrameType.payload ||
        frame.sessionId != sessionId) {
      throw const FormatException('蓝牙传输帧不属于当前内容');
    }
    final index = frame.data['index'];
    final total = frame.data['total'];
    final checksum = frame.data['checksum'];
    final content = frame.data['content'];
    if (index is! int ||
        total is! int ||
        checksum is! String ||
        content is! String ||
        total < 1 ||
        index != _nextIndex) {
      throw const FormatException('蓝牙传输分块顺序或格式错误');
    }
    if (_total != null && _total != total ||
        _checksum != null && _checksum != checksum) {
      throw const FormatException('蓝牙传输分块元数据不一致');
    }
    if (index >= total) throw const FormatException('蓝牙传输分块索引越界');
    final bytes = base64Decode(content);
    if (_bytes.length + bytes.length >
        BluetoothTransferProtocol.maxTransferBytes) {
      throw const FormatException('蓝牙传输内容超过最大长度');
    }
    _total = total;
    _checksum = checksum;
    _bytes.add(bytes);
    _nextIndex++;
  }

  Uint8List build() {
    if (!isComplete) throw const FormatException('蓝牙传输内容尚未接收完整');
    final payload = _bytes.takeBytes();
    final actualChecksum = sha256.convert(payload).toString();
    if (actualChecksum != _checksum) {
      throw const FormatException('蓝牙传输内容校验失败');
    }
    return payload;
  }
}
