import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 第三方 App 的"一键授予本地网关能力"请求。
class GatewayGrantRequest {
  final String? requestId;
  final String? sourceName;
  final String? callerPackage;

  /// 请求的模式：loopback（仅本机）或 lan（局域网）。
  final String requestedScope;
  final String? declaredSignatureSha256;

  const GatewayGrantRequest({
    this.requestId,
    this.sourceName,
    this.callerPackage,
    this.requestedScope = 'loopback',
    this.declaredSignatureSha256,
  });

  bool get wantsLan => requestedScope.toLowerCase() == 'lan';

  static GatewayGrantRequest fromPlatformMap(Map<dynamic, dynamic> map) =>
      GatewayGrantRequest(
        requestId: map['requestId'] as String?,
        sourceName: map['sourceName'] as String?,
        callerPackage: map['callerPackage'] as String?,
        requestedScope: map['requestedScope'] as String? ?? 'loopback',
        declaredSignatureSha256: map['declaredSignatureSha256'] as String?,
      );
}

/// 授权成功后的回传内容（第三方 App 拿到这些即可直接用）。
class GatewayGrantPayload {
  final String baseUrl;
  final String? token;
  final String model;
  final String scope;

  const GatewayGrantPayload({
    required this.baseUrl,
    this.token,
    required this.model,
    required this.scope,
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        if (token != null && token!.isNotEmpty) 'token': token,
        'model': model,
        'scope': scope,
        'headerName': 'X-Gateway-Token',
        'apiKey': token ?? 'apilot',
      };
}

typedef GatewayGrantRequestHandler = Future<void> Function(
    GatewayGrantRequest request);

/// 与原生侧的授权通道。
class ThirdPartyGatewayGrantChannel {
  ThirdPartyGatewayGrantChannel._();

  static final ThirdPartyGatewayGrantChannel instance =
      ThirdPartyGatewayGrantChannel._();

  static const MethodChannel _channel =
      MethodChannel('com.apilot/third_party_gateway_grant');

  GatewayGrantRequestHandler? _onRequest;

  Future<void> initialize({
    required GatewayGrantRequestHandler onRequest,
  }) async {
    _onRequest = onRequest;
    _channel.setMethodCallHandler(_handleMethodCall);
    final raw = await _channel.invokeMethod<dynamic>('getInitialGrantRequest');
    if (raw is Map) {
      await _dispatch(GatewayGrantRequest.fromPlatformMap(raw));
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onGrantRequest' || call.arguments is! Map) return;
    await _dispatch(
        GatewayGrantRequest.fromPlatformMap(call.arguments as Map));
  }

  Future<void> _dispatch(GatewayGrantRequest request) async {
    try {
      await _onRequest?.call(request);
    } catch (e) {
      debugPrint('[GatewayGrant] 处理授权请求失败: $e');
      await cancel();
    }
  }

  Future<void> complete(GatewayGrantPayload payload) {
    return _channel.invokeMethod<void>('completeGrant', {
      'payload': jsonEncode(payload.toJson()),
    });
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancelGrant');
}
