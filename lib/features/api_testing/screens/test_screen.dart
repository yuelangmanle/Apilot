import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/api_protocol_adapter.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';
import '../widgets/request_form.dart';
import '../widgets/response_viewer.dart';
import '../providers/history_provider.dart';

class TestScreen extends StatefulWidget {
  final ApiConfig apiConfig;

  /// 重测：携带历史请求的模型与请求体预填表单。
  final String? initialModel;
  final Map<String, dynamic>? initialBody;

  const TestScreen({
    super.key,
    required this.apiConfig,
    this.initialModel,
    this.initialBody,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final ApiService _apiService = ApiService();
  late ApiConfig _currentApi;
  // 请求序号：切换 API 或重复发送后，旧请求的回包直接丢弃。
  int _requestId = 0;
  bool _streamEnabled = true;
  bool _isLoading = false;
  bool _streaming = false;
  String _streamText = '';
  Map<String, dynamic>? _response;
  Map<String, String>? _responseHeaders;
  String? _errorMessage;
  int? _statusCode;
  int? _duration;
  TokenUsage? _usage;

  @override
  void initState() {
    super.initState();
    _currentApi = widget.apiConfig;
  }

  Future<void> _sendRequest(
    String model,
    String endpoint,
    Map<String, dynamic> body, {
    required bool stream,
  }) async {
    if (_isLoading) return;
    final api = _currentApi;
    final requestId = ++_requestId;
    setState(() {
      _isLoading = true;
      _streaming = stream;
      _streamText = '';
      _errorMessage = null;
      _response = null;
      _responseHeaders = null;
      _statusCode = null;
      _duration = null;
      _usage = null;
    });

    try {
      if (stream) {
        await _sendStreaming(api, model, body, requestId);
      } else {
        await _sendOnce(api, model, endpoint, body, requestId);
      }
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _isLoading = false;
        _streaming = false;
        _errorMessage = friendlyError(e);
      });
    }
  }

  Future<void> _sendOnce(
    ApiConfig api,
    String model,
    String endpoint,
    Map<String, dynamic> body,
    int requestId,
  ) async {
    final result = await _apiService.sendRequestWithHeaders(
      apiConfig: api,
      model: model,
      endpoint: endpoint,
      requestBody: body,
    );

    if (!mounted || requestId != _requestId) return;

    final responseBody = result['body'] as Map<String, dynamic>;
    setState(() {
      _response = responseBody;
      _responseHeaders = result['headers'] as Map<String, String>?;
      _statusCode = result['statusCode'] as int;
      _duration = result['duration'] as int;
      _usage = ApiProtocolAdapter.extractUsage(responseBody, api.protocolId);
      _isLoading = false;
    });
    await _recordHistory(api, model, endpoint, body, responseBody);
  }

  Future<void> _sendStreaming(
    ApiConfig api,
    String model,
    Map<String, dynamic> body,
    int requestId,
  ) async {
    await for (final event in _apiService.sendRequestStream(
      apiConfig: api,
      model: model,
      requestBody: body,
    )) {
      if (!mounted || requestId != _requestId) return;
      if (event.isDone) {
        final response = event.response!;
        setState(() {
          _response = response;
          _statusCode = 200;
          _duration = event.durationMs;
          _usage = event.usage;
          _isLoading = false;
          _streaming = false;
        });
        await _recordHistory(api, model, '/stream', body, response);
      } else {
        setState(() => _streamText += event.delta!);
      }
    }
    // 流正常关闭但没收到 done 帧（对端异常断流）时收尾。
    if (!mounted || requestId != _requestId) return;
    if (_isLoading) {
      setState(() {
        _isLoading = false;
        _streaming = false;
        if (_response == null && _streamText.isEmpty) {
          _errorMessage = '流式响应中断，未收到任何内容';
        } else if (_response == null) {
          _response = _assembledStreamFallback();
          _statusCode = 200;
        }
      });
    }
  }

  Map<String, dynamic> _assembledStreamFallback() {
    return {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': _streamText},
        }
      ],
      'model': _currentApi.selectedModel ?? '',
      'stream': true,
      'raw': '流在完成前中断，内容为已接收部分',
    };
  }

  Future<void> _recordHistory(ApiConfig api, String model, String endpoint,
      Map<String, dynamic> body, Map<String, dynamic> responseBody) async {
    final history = RequestHistory(
      id: const Uuid().v4(),
      apiConfigId: api.id,
      model: model,
      endpoint: endpoint,
      requestBody: body,
      responseBody: responseBody,
      statusCode: _statusCode,
      duration: _duration,
      promptTokens: _usage?.promptTokens,
      completionTokens: _usage?.completionTokens,
      totalTokens: _usage?.totalTokens,
    );
    try {
      await context.read<HistoryProvider>().addHistory(history);
    } catch (e) {
      // 历史落库失败不该让已成功的请求显示为失败。
      debugPrint('[Test] 保存请求历史失败: $e');
    }
  }

  String _prettyJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (_) {
      return json.toString();
    }
  }

  void _switchApi(ApiConfig api) {
    // 作废在途请求，避免旧接口的结果挂到新接口名下。
    _requestId++;
    setState(() {
      _currentApi = api;
      _response = null;
      _responseHeaders = null;
      _errorMessage = null;
      _statusCode = null;
      _duration = null;
      _usage = null;
      _streamText = '';
      _isLoading = false;
      _streaming = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('测试 ${_currentApi.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showApiSwitcher,
            tooltip: '切换API',
          ),
          if (_response != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _prettyJson(_response!)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('响应已复制'), duration: Duration(seconds: 1)),
                );
              },
              tooltip: '复制响应',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: RequestForm(
                        apiConfig: _currentApi,
                        onSubmit: (model, endpoint, body) => _sendRequest(
                            model, endpoint, body,
                            stream: _streamEnabled),
                        streamEnabled: _streamEnabled,
                        onStreamChanged: (value) =>
                            setState(() => _streamEnabled = value),
                        initialModel: widget.initialModel,
                        initialBody: widget.initialBody,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 32),
                  Expanded(child: _buildResponseArea()),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: RequestForm(
                      apiConfig: _currentApi,
                      onSubmit: (model, endpoint, body) => _sendRequest(
                          model, endpoint, body,
                          stream: _streamEnabled),
                      streamEnabled: _streamEnabled,
                      onStreamChanged: (value) =>
                          setState(() => _streamEnabled = value),
                      initialModel: widget.initialModel,
                      initialBody: widget.initialBody,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Expanded(flex: 1, child: _buildResponseArea()),
                ],
              ),
      ),
    );
  }

  void _showApiSwitcher() {
    final provider = context.read<ApiProvider>();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('切换到其他API',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...provider.apiConfigs.map((api) => ListTile(
                  leading: Icon(
                    api.id == _currentApi.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        api.id == _currentApi.id ? AppColors.primary : null,
                  ),
                  title: Text(api.name),
                  subtitle: Text(api.baseUrl,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    _switchApi(api);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseArea() {
    final secondaryTextColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    final errorColor = Theme.of(context).colorScheme.error;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading && _streaming) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('流式接收中...', style: TextStyle(color: secondaryTextColor)),
              const Spacer(),
              if (_usage?.totalTokens != null)
                Text('${_usage!.totalTokens} tokens',
                    style:
                        TextStyle(color: secondaryTextColor, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _streamText.isEmpty ? '等待第一个数据帧...' : _streamText,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('请求中...', style: TextStyle(color: secondaryTextColor)),
            const SizedBox(height: 8),
            Text('等待服务器响应',
                style:
                    TextStyle(fontSize: 12, color: secondaryTextColor)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: errorColor),
            const SizedBox(height: 16),
            const Text('请求失败',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_errorMessage!,
                  style: TextStyle(color: errorColor, fontSize: 14),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    if (_response == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 48, color: secondaryTextColor),
            const SizedBox(height: 16),
            Text('发送请求查看响应', style: TextStyle(color: secondaryTextColor)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 状态栏
        Row(
          children: [
            if (_statusCode != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_statusCode! >= 200 && _statusCode! < 300)
                      ? AppColors.success
                      : AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$_statusCode',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            if (_duration != null) ...[
              const SizedBox(width: 12),
              Text('${_duration}ms',
                  style: TextStyle(color: secondaryTextColor, fontSize: 13)),
            ],
            if (_usage?.totalTokens != null) ...[
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_usage!.totalTokens} tokens'
                  '${_usage!.promptTokens != null && _usage!.completionTokens != null ? ' (${_usage!.promptTokens}+${_usage!.completionTokens})' : ''}',
                  style:
                      TextStyle(color: secondaryTextColor, fontSize: 12),
                ),
              ),
            ],
            const Spacer(),
            if (_responseHeaders != null)
              TextButton.icon(
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Headers'),
                onPressed: _showHeaders,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: ResponseViewer(response: _response, isLoading: false)),
      ],
    );
  }

  void _showHeaders() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('响应 Headers'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: (_responseHeaders ?? {})
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'monospace')),
                            ),
                            Expanded(
                                child: Text(e.value,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace'))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = (_responseHeaders ?? {})
                  .entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Headers已复制')));
            },
            child: const Text('复制'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭')),
        ],
      ),
    );
  }
}
