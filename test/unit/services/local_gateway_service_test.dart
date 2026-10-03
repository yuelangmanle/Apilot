import 'dart:convert';
import 'dart:io';

import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/features/sync/services/local_gateway_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.autoUncompress = true;
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final supportDirectory =
      Directory.systemTemp.createTempSync('local_gateway_service_test_');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return supportDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    await LocalGatewayService.stop();
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  });

  test('健康检查与诊断接口只读返回状态', () async {
    final config = ApiConfig(
      id: 'gateway-test',
      name: '网关测试配置',
      baseUrl: 'http://127.0.0.1:1/v1',
      apiKey: 'not-returned',
      models: const ['test-model'],
      environment: 'test',
    );
    await LocalGatewayService.start(config, port: 0);

    await HttpOverrides.runZoned(() async {
      final client = HttpClient();
      try {
        final health = await (await client.getUrl(Uri.parse(
                'http://127.0.0.1:${LocalGatewayService.port}/v1/health')))
            .close();
        final healthBody =
            jsonDecode(await health.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        expect(health.statusCode, HttpStatus.ok);
        expect(healthBody['object'], 'apilot.health');
        expect(healthBody['service']['mode'], 'cloud_proxy');
        expect(jsonEncode(healthBody), isNot(contains('not-returned')));

        final diagnostics = await (await client.getUrl(Uri.parse(
                'http://127.0.0.1:${LocalGatewayService.port}/v1/diagnostics')))
            .close();
        final diagnosticsBody =
            jsonDecode(await diagnostics.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        expect(diagnostics.statusCode, HttpStatus.ok);
        expect(diagnosticsBody['object'], 'apilot.diagnostics');
        expect(diagnosticsBody, contains('tools'));
        expect(diagnosticsBody, contains('downloads'));
      } finally {
        client.close(force: true);
      }
    }, createHttpClient: (context) {
      return _RealHttpOverrides().createHttpClient(context);
    });
  });
}
