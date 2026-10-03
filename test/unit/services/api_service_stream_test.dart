import 'dart:convert';
import 'dart:io';

import 'package:api_manager/core/models/api_config.dart';
import 'package:api_manager/core/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => server.close(force: true));

  ApiConfig config() => ApiConfig(
        id: 'stream-test',
        name: '本地测试服务',
        baseUrl: 'http://${server.address.address}:${server.port}/v1',
        apiKey: 'test-key',
        models: const ['test-model'],
        environment: 'test',
      );

  test('兼容 200 application/json 的非 SSE 云端响应', () async {
    server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'model': 'test-model',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'HTML 已生成'},
          }
        ],
      }));
      request.response.close();
    });

    final events = await ApiService().sendRequestStream(
      apiConfig: config(),
      model: 'test-model',
      requestBody: {
        'messages': [
          {'role': 'user', 'content': '写一个 HTML'},
        ],
      },
    ).toList();

    expect(events.where((event) => event.delta == 'HTML 已生成'), hasLength(1));
    expect(events.last.isDone, isTrue);
  });

  test('处理没有空行结尾的 SSE 最后一帧', () async {
    server.listen((request) {
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write('data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '最后一帧'},
              }
            ],
          })}');
      request.response.close();
    });

    final events = await ApiService().sendRequestStream(
      apiConfig: config(),
      model: 'test-model',
      requestBody: {
        'messages': [
          {'role': 'user', 'content': '测试'},
        ],
      },
    ).toList();

    expect(events.where((event) => event.delta == '最后一帧'), hasLength(1));
    expect(events.last.isDone, isTrue);
  });
}
