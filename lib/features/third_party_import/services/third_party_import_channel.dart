import 'package:flutter/services.dart';

import '../models/third_party_import_models.dart';

typedef ThirdPartyImportRequestHandler = Future<void> Function(
  ThirdPartyImportRequest request,
);

class ThirdPartyImportChannel {
  ThirdPartyImportChannel._();

  static final ThirdPartyImportChannel instance = ThirdPartyImportChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.apilot/third_party_import',
  );

  bool _initialized = false;
  ThirdPartyImportRequestHandler? _onRequest;

  Future<void> initialize({
    required ThirdPartyImportRequestHandler onRequest,
  }) async {
    _onRequest = onRequest;

    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_handleMethodCall);
    }

    final initialRequest = await _readInitialRequest();
    if (initialRequest != null) {
      await _dispatch(initialRequest);
    }
  }

  Future<ThirdPartyImportRequest?> _readInitialRequest() async {
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
      'getInitialImportRequest',
    );
    if (raw == null) return null;
    return ThirdPartyImportRequest.fromPlatformMap(raw);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onImportRequest') {
      final method = call.method;
      throw PlatformException(
        code: 'not_implemented',
        message: 'Unsupported method: $method',
      );
    }

    final arguments = call.arguments;
    if (arguments is Map) {
      await _dispatch(ThirdPartyImportRequest.fromPlatformMap(arguments));
    }
    return null;
  }

  Future<void> _dispatch(ThirdPartyImportRequest request) async {
    final handler = _onRequest;
    if (handler != null) {
      await handler(request);
    }
  }
}
