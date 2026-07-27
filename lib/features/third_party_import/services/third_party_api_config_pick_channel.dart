import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/third_party_import_models.dart';

typedef ThirdPartyApiConfigPickRequestHandler = Future<void> Function(
  ThirdPartyApiConfigPickRequest request,
);

class ThirdPartyApiConfigPickChannel {
  ThirdPartyApiConfigPickChannel._();

  static final ThirdPartyApiConfigPickChannel instance =
      ThirdPartyApiConfigPickChannel._();

  static const MethodChannel _channel = MethodChannel(
    'com.apilot/third_party_api_config_pick',
  );

  ThirdPartyApiConfigPickRequestHandler? _onRequest;

  Future<void> initialize({
    required ThirdPartyApiConfigPickRequestHandler onRequest,
  }) async {
    _onRequest = onRequest;
    _channel.setMethodCallHandler(_handleMethodCall);

    final request = await _readInitialRequest();
    if (request != null) {
      await _dispatch(request);
    }
  }

  Future<ThirdPartyApiConfigPickRequest?> _readInitialRequest() async {
    final raw = await _channel.invokeMethod<dynamic>('getInitialPickRequest');
    if (raw is! Map) return null;
    return ThirdPartyApiConfigPickRequest.fromPlatformMap(raw);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onPickRequest' || call.arguments is! Map) return;
    await _dispatch(
      ThirdPartyApiConfigPickRequest.fromPlatformMap(call.arguments as Map),
    );
  }

  Future<void> _dispatch(ThirdPartyApiConfigPickRequest request) async {
    await _onRequest?.call(request);
  }

  Future<void> complete(ThirdPartyApiConfigPickPayload payload) {
    return _channel.invokeMethod<void>(
      'completePick',
      <String, dynamic>{'payload': jsonEncode(payload.toJson())},
    );
  }

  Future<void> cancel() {
    return _channel.invokeMethod<void>('cancelPick');
  }
}
