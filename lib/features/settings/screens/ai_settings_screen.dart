import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ai/ai_service.dart';
import '../../../core/services/local_llm/local_llm_engine.dart';
import '../../../core/services/local_llm/model_download_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_management/providers/api_provider.dart';

/// AI 功能设置：选择使用哪个 API 配置或本地模型来接管 AI 功能。
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  static const _aiSourceKey = 'apilot_ai_source';
  static const _aiEnabledKey = 'apilot_ai_enabled';

  String? _selectedConfigId;
  String? _selectedLocalModelName;
  List<DownloadedModel> _localModels = [];
  bool _useLocalModel = false;
  bool _aiEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedConfigId = prefs.getString(_aiSourceKey);
      _useLocalModel = prefs.getBool('apilot_ai_use_local') ?? false;
      final savedLocal = prefs.getString('apilot_ai_local_model');
      final files = await ModelDownloadService.listDownloadedModels();
      _localModels = files.map((f) => DownloadedModel.fromFile(f)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _selectedLocalModelName = savedLocal ??
          (_localModels.isEmpty ? null : _localModels.first.fileName);
      if (_selectedLocalModelName != null &&
          !_localModels.any((m) => m.fileName == _selectedLocalModelName)) {
        _selectedLocalModelName =
            _localModels.isEmpty ? null : _localModels.first.fileName;
      }
      _aiEnabled = prefs.getBool(_aiEnabledKey) ?? true;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_aiSourceKey, _selectedConfigId ?? '');
      await prefs.setBool('apilot_ai_use_local', _useLocalModel);
      await prefs.setBool(_aiEnabledKey, _aiEnabled);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final configs = context.watch<ApiProvider>().allApiConfigs;
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              _save();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  title: const Text('启用 AI 功能'),
                  subtitle:
                      const Text('错误诊断 / 粘贴识别兜底 / 用量分析'),
                  value: _aiEnabled,
                  onChanged: (value) => setState(() => _aiEnabled = value),
                  secondary: const Icon(Icons.auto_awesome),
                ),
                const Divider(height: 24),
                // 当前生效状态：用户配完能立刻看到 AI 到底会不会工作。
                FutureBuilder<String>(
                  future: AiService.sourceDescription(configs),
                  builder: (context, snapshot) => Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline,
                          color: AppColors.primary, size: 20),
                      title: Text(
                        _aiEnabled
                            ? '当前生效：${snapshot.data ?? '检测中…'}'
                            : 'AI 功能已关闭',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        _aiEnabled
                            ? (_useLocalModel
                                ? '本地模型需先在模型商店下载；未加载时首次调用会自动加载（较慢）'
                                : '调用失败会回退到本地启发式，不影响主流程')
                            : '打开上面的开关后，错误诊断/用量分析/识别兜底才会生效',
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 24),
                Text('AI 引擎来源',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: secondary)),
                const SizedBox(height: 8),
                ListTile(
                  title: const Text('云端 API 配置'),
                  subtitle: const Text('使用下方选择的 API 配置'),
                  leading: Icon(
                    !_useLocalModel
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: !_useLocalModel
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  onTap: () => setState(() => _useLocalModel = false),
                ),
                if (!_useLocalModel)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedConfigId,
                      decoration: const InputDecoration(
                        labelText: '选择 API 配置',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: configs
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedConfigId = value),
                    ),
                  ),
                ListTile(
                  title: const Text('本地模型'),
                  subtitle: const Text('使用模型商店中已下载的本地模型（完全离线）'),
                  leading: Icon(
                    _useLocalModel
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _useLocalModel
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  onTap: () => setState(() => _useLocalModel = true),
                ),
                if (_useLocalModel)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: _localModels.isEmpty
                        ? Text('还没有已下载的本地模型：先到「模型」页下载',
                            style: TextStyle(fontSize: 12, color: secondary))
                        : DropdownButtonFormField<String>(
                            initialValue: _selectedLocalModelName,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '使用哪个本地模型（实时生效）',
                              helperText: '选择后 AI 功能会立刻改用这个模型',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final model in _localModels)
                                DropdownMenuItem(
                                  value: model.fileName,
                                  child: Text(
                                      '${model.name} · ${model.sizeMb}',
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              setState(() => _selectedLocalModelName = value);
                              final picked = _localModels
                                  .firstWhere((m) => m.fileName == value);
                              final messenger = ScaffoldMessenger.of(context);
                              await AiService.setPreferredLocalModel(
                                  picked.filePath);
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '已切换到 ${picked.name}（下次调用生效）'),
                                      backgroundColor: AppColors.success),
                                );
                              }
                            },
                          ),
                  ),
                const SizedBox(height: 16),
                Text('使用说明',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: secondary)),
                const SizedBox(height: 8),
                Text(
                  '· AI 功能包括：错误诊断、粘贴识别兜底、请求体生成、用量分析\n'
                  '· 不会将你的 API Key 发送给 AI——只发送任务相关的上下文\n'
                  '· 云端配置使用你已有的 API Key，本地模型完全离线',
                  style:
                      TextStyle(fontSize: 12, height: 1.6, color: secondary),
                ),
              ],
            ),
    );
  }
}
