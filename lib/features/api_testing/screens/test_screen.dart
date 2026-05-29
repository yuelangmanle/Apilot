import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';
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
  Map<String, dynamic>? _response;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _sendRequest(String model, String endpoint, Map<String, dynamic> body) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _response = null;
    });

    try {
      final response = await _apiService.sendRequest(
        apiConfig: widget.apiConfig,
        model: model,
        endpoint: endpoint,
        requestBody: body,
      );

      setState(() {
        _response = response;
        _isLoading = false;
      });

      // 保存到历史
      if (mounted) {
        final history = RequestHistory(
          id: const Uuid().v4(),
          apiConfigId: widget.apiConfig.id,
          model: model,
          endpoint: endpoint,
          requestBody: body,
          responseBody: response['body'] as Map<String, dynamic>?,
          statusCode: response['statusCode'] as int?,
          duration: response['duration'] as int?,
        );
        context.read<HistoryProvider>().addHistory(history);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('测试 ${widget.apiConfig.name}'),
        actions: [
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
                        apiConfig: widget.apiConfig,
                        onSubmit: _sendRequest,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 32),
                  Expanded(
                    child: _buildResponseArea(),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: RequestForm(
                      apiConfig: widget.apiConfig,
                      onSubmit: _sendRequest,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Expanded(
                    flex: 1,
                    child: _buildResponseArea(),
                  ),
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
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
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

    return ResponseViewer(response: _response, isLoading: false);
  }
}
