import 'dart:async';
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

  test('停止流式请求会关闭连接且不产生伪造的完成事件', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    server.listen((request) async {
      if (!received.isCompleted) received.complete();
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      try {
        await release.future;
        request.response.write('data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': '不应到达'},
                }
              ],
            })}\n\n');
        await request.response.close();
      } catch (_) {}
    });

    final cancellation = ApiRequestCancellation();
    final eventsFuture = ApiService()
        .sendRequestStream(
          apiConfig: config(),
          model: 'test-model',
          requestBody: {
            'messages': [
              {'role': 'user', 'content': '停止'},
            ],
          },
          cancellation: cancellation,
        )
        .toList();
    await received.future.timeout(const Duration(seconds: 2));
    cancellation.cancel();
    final events = await eventsFuture.timeout(const Duration(seconds: 2));
    expect(events, isEmpty);
    if (!release.isCompleted) release.complete();
  });

  test('主 Key 失败后下次请求优先使用健康的备用 Key', () async {
    final seenKeys = <String>[];
    server.listen((request) async {
      await request.drain<void>();
      seenKeys.add(request.headers.value('authorization') ?? '');
      final unauthorized = seenKeys.length == 1;
      request.response.statusCode = unauthorized ? 401 : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(unauthorized
          ? {'error': 'invalid key'}
          : {
              'model': 'test-model',
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'ok'},
                }
              ],
            }));
      await request.response.close();
    });

    final apiConfig = ApiConfig(
      id: 'key-pool-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Key 池测试',
      baseUrl: 'http://${server.address.address}:${server.port}/v1',
      apiKey: 'primary-key',
      models: const ['test-model'],
      environment: 'test',
      metadata: const {
        'extraKeys': ['backup-key'],
      },
    );

    final first = await ApiService().sendRequest(
      apiConfig: apiConfig,
      model: 'test-model',
      endpoint: '',
      requestBody: const {'messages': []},
    );
    expect(first['statusCode'], 200);
    expect(seenKeys, ['Bearer primary-key', 'Bearer backup-key']);

    final second = await ApiService().sendRequest(
      apiConfig: apiConfig,
      model: 'test-model',
      endpoint: '',
      requestBody: const {'messages': []},
    );
    expect(second['statusCode'], 200);
    expect(seenKeys.last, 'Bearer backup-key');
  });
}
