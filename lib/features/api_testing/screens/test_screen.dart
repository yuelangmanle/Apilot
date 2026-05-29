import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_management/providers/api_provider.dart';
import '../widgets/request_form.dart';
import '../widgets/response_viewer.dart';
import '../providers/history_provider.dart';

class TestScreen extends StatefulWidget {
  final ApiConfig apiConfig;

  const TestScreen({super.key, required this.apiConfig});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final ApiService _apiService = ApiService();
  late ApiConfig _currentApi;
  Map<String, dynamic>? _response;
  Map<String, String>? _responseHeaders;
  bool _isLoading = false;
  String? _errorMessage;
  int? _statusCode;
  int? _duration;

  @override
  void initState() {
    super.initState();
    _currentApi = widget.apiConfig;
  }

  Future<void> _sendRequest(String model, String endpoint, Map<String, dynamic> body) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _response = null;
      _responseHeaders = null;
      _statusCode = null;
      _duration = null;
    });

    try {
      final result = await _apiService.sendRequestWithHeaders(
        apiConfig: _currentApi,
        model: model,
        endpoint: endpoint,
        requestBody: body,
      );

      setState(() {
        _response = result['body'] as Map<String, dynamic>;
        _responseHeaders = result['headers'] as Map<String, String>?;
        _statusCode = result['statusCode'] as int;
        _duration = result['duration'] as int;
        _isLoading = false;
      });

      if (mounted) {
        final history = RequestHistory(
          id: const Uuid().v4(),
          apiConfigId: _currentApi.id,
          model: model,
          endpoint: endpoint,
          requestBody: body,
          responseBody: _response,
          statusCode: _statusCode,
          duration: _duration,
        );
        context.read<HistoryProvider>().addHistory(history);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  String _friendlyError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return '无法连接到服务器，请检查网络和API地址是否正确';
    }
    if (msg.contains('TimeoutException') || msg.contains('timeout')) {
      return '请求超时，服务器响应太慢';
    }
    if (msg.contains('Connection refused')) {
      return '连接被拒绝，请检查API地址和端口';
    }
    if (msg.contains('HandshakeException')) {
      return 'SSL握手失败，请检查HTTPS配置';
    }
    return '请求失败: $msg';
  }

  void _switchApi(ApiConfig api) {
    setState(() {
      _currentApi = api;
      _response = null;
      _responseHeaders = null;
      _errorMessage = null;
      _statusCode = null;
      _duration = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('测试 ${_currentApi.name}'),
        actions: [
          // 切换API按钮
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showApiSwitcher,
            tooltip: '切换API',
          ),
          if (_response != null)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _response.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('响应已复制'), duration: Duration(seconds: 1)),
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
                        onSubmit: _sendRequest,
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
                    child: RequestForm(apiConfig: _currentApi, onSubmit: _sendRequest),
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
              child: Text('切换到其他API', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...provider.apiConfigs.map((api) => ListTile(
              leading: Icon(
                api.id == _currentApi.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: api.id == _currentApi.id ? AppColors.primary : null,
              ),
              title: Text(api.name),
              subtitle: Text(api.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('请求中...', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 8),
            Text('等待服务器响应', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text('请求失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 14), textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }

    if (_response == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('发送请求查看响应', style: TextStyle(color: AppColors.textSecondary)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_statusCode! >= 200 && _statusCode! < 300) ? AppColors.success : AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$_statusCode', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            if (_duration != null) ...[
              const SizedBox(width: 12),
              Text('${_duration}ms', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            const Spacer(),
            if (_responseHeaders != null)
              TextButton.icon(
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Headers'),
                onPressed: _showHeaders,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
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
              children: (_responseHeaders ?? {}).entries.map((e) =>
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
                      ),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                    ],
                  ),
                ),
              ).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final text = (_responseHeaders ?? {}).entries.map((e) => '${e.key}: ${e.value}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Headers已复制')));
            },
            child: const Text('复制'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }
}
