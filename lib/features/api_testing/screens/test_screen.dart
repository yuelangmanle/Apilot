import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/api_config.dart';
import '../../../core/models/request_history.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/theme/color_scheme.dart';
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

  Future<void> _sendRequest(String model, String endpoint, Map<String, dynamic> body) async {
    setState(() {
      _isLoading = true;
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

      // Save to history
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
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请求失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('测试 ${widget.apiConfig.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              if (_response != null) {
                // Copy response
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('响应已复制')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
              child: ResponseViewer(
                response: _response,
                isLoading: _isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
