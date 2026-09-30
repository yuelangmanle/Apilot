import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_protocol_adapter.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/cost_estimator.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../api_management/providers/api_provider.dart';

/// 对比测试：同一请求发往多个配置，并排比较状态/耗时/token/成本。
/// 这是"多 Key 多供应商"用户最独特的工作流。
class CompareTestScreen extends StatefulWidget {
  final ApiConfig initialConfig;

  const CompareTestScreen({super.key, required this.initialConfig});

  @override
  State<CompareTestScreen> createState() => _CompareTestScreenState();
}

class _CompareResult {
  final ApiConfig config;
  final String model;
  int? statusCode;
  int? durationMs;
  int? totalTokens;
  double? costUsd;
  String? error;
  bool running = false;

  _CompareResult(this.config, this.model);
}

class _CompareTestScreenState extends State<CompareTestScreen> {
  final Set<String> _selectedIds = {};
  bool _running = false;
  final Map<String, _CompareResult> _results = {};
  final _bodyController = TextEditingController();
  String _model = '';

  @override
  void initState() {
    super.initState();
    _selectedIds.add(widget.initialConfig.id);
    final initial = widget.initialConfig.selectedModel ??
        (widget.initialConfig.models.isEmpty
            ? ''
            : widget.initialConfig.models.first);
    _model = initial;
    _bodyController.text = '''
{
  "messages": [{"role": "user", "content": "用一句话介绍你自己"}],
  "temperature": 0.5
}''';
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running || _selectedIds.isEmpty) return;
    Map<String, dynamic> body;
    try {
      final raw = _bodyController.text.isEmpty ? '{}' : _bodyController.text;
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请求体不是有效 JSON'), backgroundColor: AppColors.error),
      );
      return;
    }

    final configs = context.read<ApiProvider>().allApiConfigs;
    final targets = configs.where((c) => _selectedIds.contains(c.id)).toList();
    setState(() {
      _running = true;
      _results.clear();
      for (final config in targets) {
        _results[config.id] = _CompareResult(config, _model);
      }
    });
    final messenger = ScaffoldMessenger.of(context);

    // 逐个串行执行，避免对同一服务商并发。
    for (final config in targets) {
      final result = _results[config.id]!;
      if (!mounted) return;
      setState(() => result.running = true);
      final stopwatch = Stopwatch()..start();
      try {
        final response = await ApiService().sendRequest(
          apiConfig: config,
          model: _model,
          endpoint: '',
          requestBody: body,
        );
        stopwatch.stop();
        result.statusCode = response['statusCode'] as int;
        result.durationMs = response['duration'] as int;
        final usage = ApiProtocolAdapter.extractUsage(
            response['body'] as Map<String, dynamic>, config.protocolId);
        result.totalTokens = usage?.totalTokens;
        final prompt = (usage?.promptTokens ?? 0) / 1000000;
        final completion = (usage?.completionTokens ?? 0) / 1000000;
        final price = CostEstimator.priceFor(_model);
        result.costUsd =
            prompt * price.inputPerMillion + completion * price.outputPerMillion;
      } catch (e) {
        stopwatch.stop();
        result.error = friendlyError(e);
        result.durationMs = stopwatch.elapsedMilliseconds;
      }
      if (!mounted) return;
      setState(() => result.running = false);
    }
    _running = false;
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      const SnackBar(
          content: Text('对比完成'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('对比测试')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _bodyController,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '请求体（共享）',
                hintText: 'messages 等字段；model 会自动覆盖',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '模型名（各配置共享，需各自支持）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => _model = value.trim(),
              controller: TextEditingController(text: _model),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final config in configs)
                  CheckboxListTile(
                    dense: true,
                    value: _selectedIds.contains(config.id),
                    title: Text(config.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(config.baseUrl,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onChanged: _running
                        ? null
                        : (checked) => setState(() {
                              if (checked == true) {
                                _selectedIds.add(config.id);
                              } else {
                                _selectedIds.remove(config.id);
                              }
                            }),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed:
                  _running || _selectedIds.length < 2 ? null : _run,
              icon: const Icon(Icons.compare_arrows),
              label: Text(_running
                  ? '对比中...'
                  : '开始对比（已选 ${_selectedIds.length} 个）'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child:
                        Text('选择 2 个以上配置后开始对比', style: TextStyle(color: secondary)))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: _results.values.map((result) {
                      final ok =
                          result.statusCode != null && result.statusCode! < 300;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: result.running
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Icon(
                                  ok
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  color: ok
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                          title: Text(result.config.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            result.error ??
                                '状态 ${result.statusCode} · '
                                    '${result.durationMs ?? '-'}ms · '
                                    '${result.totalTokens ?? '-'} tokens',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                          trailing: Text(
                            result.costUsd == null
                                ? '-'
                                : CostEstimator.formatUsd(result.costUsd!),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
