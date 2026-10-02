import 'dart:io';

import 'package:api_manager/core/services/ai/tool_registry.dart';
import 'package:api_manager/core/services/local_llm/download_task_store.dart';
import 'package:api_manager/core/services/local_llm/model_capabilities.dart';
import 'package:api_manager/core/services/local_llm/model_catalog.dart';
import 'package:api_manager/core/services/local_llm/model_plaza_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ToolRegistry 调用协议', () {
    setUp(() {
      ToolRegistry.resetForTest();
    });

    test('解析 @@TOOL 行（含中文参数）', () {
      final call = ToolRegistry.parseCall(
          '@@TOOL {"name":"web_search","args":{"query":"今天的天气"}}');
      expect(call, isNotNull);
      expect(call!.name, 'web_search');
      expect(call.args['query'], '今天的天气');
    });

    test('普通回答不误判为工具调用', () {
      expect(ToolRegistry.parseCall('今天北京晴，气温 22 度。'), isNull);
      expect(ToolRegistry.parseCall('提到 @@TOOL 但格式不对'), isNull);
    });

    test('stripCall 去掉协议行后再给用户看', () {
      final text = ToolRegistry.stripCall(
          '@@TOOL {"name":"calculator","args":{"expression":"1+1"}}\n'
          '计算结果是 2。');
      expect(text, '计算结果是 2。');
      expect(text.contains('@@TOOL'), isFalse);
    });

    test('未知工具返回明确错误而不是抛异常', () async {
      final result = await ToolRegistry.execute('not_a_tool', {});
      expect(result, contains('没有名为'));
    });

    test('calculator 能算且拒绝非法表达式', () async {
      ToolRegistry.registerBuiltins();
      expect(await ToolRegistry.execute('calculator',
          {'expression': '(1+2)*3'}), contains('9'));
      final bad = await ToolRegistry.execute(
          'calculator', {'expression': 'import os; os.system("x")'});
      expect(bad, contains('不合法'));
      final divideByZero = await ToolRegistry.execute(
          'calculator', {'expression': '1/0'});
      expect(divideByZero, anyOf(contains('不合法'), contains('除零')));
    });

    test('工具说明会注入模型（描述里含协议格式）', () {
      ToolRegistry.registerBuiltins();
      final doc = ToolRegistry.describeForPrompt();
      expect(doc, contains('@@TOOL'));
      expect(doc, contains('web_search'));
      expect(doc, contains('save_html'));
    });
  });

  group('isPublicHost（联网工具的安全边界）', () {
    test('公网域名与地址放行', () {
      expect(isPublicHost('huggingface.co'), isTrue);
      expect(isPublicHost('8.8.8.8'), isTrue);
      expect(isPublicHost('1.1.1.1'), isTrue);
    });

    test('本机/内网/保留地址一律拒绝', () {
      expect(isPublicHost('localhost'), isFalse);
      expect(isPublicHost('127.0.0.1'), isFalse);
      expect(isPublicHost('10.0.0.5'), isFalse);
      expect(isPublicHost('192.168.1.10'), isFalse);
      expect(isPublicHost('172.16.0.1'), isFalse);
      expect(isPublicHost('169.254.1.1'), isFalse);
      expect(isPublicHost('0.0.0.0'), isFalse);
      expect(isPublicHost('::1'), isFalse);
      expect(isPublicHost('fd00::1'), isFalse);
      expect(isPublicHost('something.local'), isFalse);
    });
  });

  group('DownloadTask 持久化', () {
    test('失败任务也进记录（含错误与已下字节）', () async {
      final dir = Directory.systemTemp.createTempSync('dl_task_test');
      // DownloadTaskStore 走 path_provider，这里直接验证模型本身的可序列化性。
      final task = DownloadTask(
        id: 'gemma-3-1b',
        url: 'https://example.com/gemma.gguf',
        fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
        status: 'failed',
        receivedBytes: 413000000,
        totalBytes: 0,
        error: 'Connection closed',
        updatedAt: DateTime.now(),
      );
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.status, 'failed');
      expect(restored.error, 'Connection closed');
      expect(restored.receivedBytes, 413000000);
      expect(restored.isFailed, isTrue);
      expect(restored.receivedLabel, contains('MB'));
      // copyWith 重试后状态可回到下载中并清掉错误。
      final retried = restored.copyWith(status: 'downloading', clearError: true);
      expect(retried.error, isNull);
      expect(retried.isActive, isTrue);
      dir.deleteSync(recursive: true);
    });
  });

  group('PlazaModel 能力标签', () {
    test('仓库有 mmproj → 标"看图"（文件事实，不靠猜名字）', () {
      const model = PlazaModel(
        info: LocalModelInfo(
          id: 'hf_x',
          name: 'gemma-3-4b-it',
          description: '',
          downloadUrl: 'https://example.com/a.gguf',
          sizeBytes: 2000000000,
          quantization: 'Q4_K_M',
          ramRequired: '~3 GB',
        ),
        hasProjector: true,
        projector: ModelFileVariant(
          fileName: 'mmproj-F16.gguf',
          downloadUrl: 'https://example.com/mmproj-F16.gguf',
          sizeBytes: 790000000,
          quantization: 'F16',
        ),
        supportsThinking: false,
        sourceLabel: 'HuggingFace',
      );
      expect(model.capabilityTags, contains('看图'));
      // 打包大小要把投影算进去（用户得下两个文件）。
      expect(model.bundleSizeGb, greaterThan(2.5));
    });

    test('纯文本仓库不带看图标签', () {
      const model = PlazaModel(
        info: LocalModelInfo(
          id: 'hf_y',
          name: 'gemma-3-1b-it',
          description: '',
          downloadUrl: 'https://example.com/b.gguf',
          sizeBytes: 800000000,
          quantization: 'Q4_K_M',
          ramRequired: '~1.5 GB',
        ),
        hasProjector: false,
        supportsThinking: false,
        sourceLabel: 'HuggingFace',
      );
      expect(model.capabilityTags, isNot(contains('看图')));
      expect(model.capabilityTags, isNot(contains('中文')));
    });

    test('思考模型标深度思考，中文模型标中文', () {
      const model = PlazaModel(
        info: LocalModelInfo(
          id: 'hf_z',
          name: 'Qwen3-4B-GGUF',
          description: '',
          downloadUrl: 'https://example.com/c.gguf',
          sizeBytes: 2000000000,
          quantization: 'Q4_K_M',
          ramRequired: '~3 GB',
        ),
        hasProjector: false,
        supportsThinking: true,
        sourceLabel: 'HuggingFace',
      );
      expect(model.capabilityTags, containsAll(['深度思考', '中文']));
    });
  });

  group('投影匹配（mmproj 不通用）', () {
    test('coreToken 去掉量化后缀', () {
      expect(ModelCapabilities.coreToken('gemma-3-4b-it-Q4_K_M.gguf'),
          'gemma-3-4b-it');
      expect(ModelCapabilities.coreToken('Qwen2.5-VL-7B-Instruct-Q8_0.gguf'),
          'qwen2.5-vl-7b-instruct');
      expect(ModelCapabilities.coreToken('model-f16.gguf'), 'model');
    });

    test('isProjectorFile 只认 mmproj*.gguf', () {
      expect(ModelCapabilities.isProjectorFile('mmproj-F16.gguf'), isTrue);
      expect(ModelCapabilities.isProjectorFile('gemma-3-4b-it-Q4_K_M.gguf'),
          isFalse);
    });
  });

  group('内置目录与商店数据', () {
    test('多模态内置模型必须同时给出投影地址（否则标了也看不了图）', () {
      for (final model in LocalModelCatalog.builtin) {
        if (model.tags.contains('多模态')) {
          expect(model.mmProjUrl, isNotNull,
              reason: '${model.name} 标了多模态就必须带 mmproj 地址');
          expect(model.mmProjUrl, startsWith('https://'));
        }
      }
    });

    test('mmproj 文件名都符合 mmproj 前缀约定（引擎按此识别）', () {
      for (final model in LocalModelCatalog.builtin) {
        final url = model.mmProjUrl;
        if (url == null) continue;
        final fileName = p.basename(url);
        expect(ModelCapabilities.isProjectorFile(fileName), isTrue,
            reason: '$fileName 必须以 mmproj 开头且是 .gguf');
      }
    });
  });
}
