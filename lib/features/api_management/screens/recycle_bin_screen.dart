import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/api_config.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/responsive_layout.dart';
import '../../api_testing/providers/history_provider.dart';
import '../providers/api_provider.dart';

/// 回收站：删除的 API 方案在此保留 [retentionDays] 天，期间可恢复，
/// 到期后在打开本页或应用启动时自动清除。
class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  static const _retentionPrefsKey = 'apilot_recycle_retention_days';
  static const _retentionChoices = [7, 14, 30];

  final DatabaseService _databaseService = DatabaseService();
  List<ApiConfig> _deleted = [];
  int _retentionDays = 7;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _retentionDays = prefs.getInt(_retentionPrefsKey) ?? 7;
      // 打开时先清理到期的，再展示剩余内容。
      final cutoff = DateTime.now().subtract(Duration(days: _retentionDays));
      await _databaseService.purgeExpiredApiConfigs(cutoff);
      final deleted = await _databaseService.getDeletedApiConfigs();
      if (!mounted) return;
      setState(() => _deleted = deleted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRetention(int days) async {
    if (days == _retentionDays) return;
    // 变更保留期会对现有条目立即生效：缩短可能提前清除，明确告知。
    final shortenRisk = _deleted.any((config) {
      final deletedAt = config.deletedAt;
      if (deletedAt == null) return false;
      return days < _retentionDays &&
          deletedAt
              .add(Duration(days: days))
              .isBefore(DateTime.now());
    });
    var confirmed = true;
    if (shortenRisk && mounted) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('缩短保留期'),
              content: const Text(
                  '部分回收站条目按新保留期已到期，下次打开回收站时将被自动清除。继续吗？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('继续')),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retentionPrefsKey, days);
    setState(() => _retentionDays = days);
  }

  DateTime _purgeDeadline(ApiConfig config) {
    final deletedAt = config.deletedAt ?? DateTime.now();
    return deletedAt.add(Duration(days: _retentionDays));
  }

  int _remainingDays(ApiConfig config) {
    final deadline = _purgeDeadline(config);
    final remaining = deadline.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _restore(ApiConfig config) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final apiProvider = context.read<ApiProvider>();
    try {
      await apiProvider.restoreFromRecycleBin(config.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已恢复「${config.name}」'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 1),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purge(ApiConfig config) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text(
            '「${config.name}」及其请求历史将被永久删除，无法恢复。确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final apiProvider = context.read<ApiProvider>();
    final historyProvider = context.read<HistoryProvider>();
    try {
      await apiProvider.purgeFromRecycleBin(config.id);
      // 彻底删除会连带请求历史：同步刷新历史页内存数据。
      unawaited(historyProvider.loadHistory());
      messenger.showSnackBar(
        SnackBar(
            content: Text('已永久删除「${config.name}」'),
            duration: const Duration(seconds: 1)),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    if (_deleted.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除全部 ${_deleted.length} 个方案及其请求历史，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final apiProvider = context.read<ApiProvider>();
    final historyProvider = context.read<HistoryProvider>();
    try {
      final purged = await apiProvider.clearRecycleBin();
      unawaited(historyProvider.loadHistory());
      messenger.showSnackBar(
        SnackBar(
            content: Text('已清空 $purged 个方案'),
            duration: const Duration(seconds: 1)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('自动清除时间',
                  style: TextStyle(fontSize: 13, color: secondary)),
              const Spacer(),
              DropdownButton<int>(
                value: _retentionDays,
                underline: const SizedBox.shrink(),
                items: _retentionChoices
                    .map((days) => DropdownMenuItem(
                          value: days,
                          child: Text('$days 天'),
                        ))
                    .toList(),
                onChanged: (days) {
                  if (days != null) _setRetention(days);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _deleted.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline,
                              size: 56, color: secondary),
                          const SizedBox(height: 12),
                          Text('回收站是空的',
                              style: TextStyle(
                                  fontSize: 16, color: secondary)),
                          const SizedBox(height: 6),
                          Text('删除的方案会在这里保留 $_retentionDays 天',
                              style: TextStyle(
                                  fontSize: 12, color: secondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _deleted.length,
                      itemBuilder: (context, index) {
                        final config = _deleted[index];
                        return _buildDeletedCard(context, config, secondary);
                      },
                    ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: '清空回收站',
            onPressed: _deleted.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: isWide ? CenteredContent(maxWidth: 640, child: content) : content,
    );
  }

  Widget _buildDeletedCard(
      BuildContext context, ApiConfig config, Color secondary) {
    final remaining = _remainingDays(config);
    final deletedAt = config.deletedAt ?? DateTime.now();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            config.name.isEmpty ? '?' : config.name.characters.first,
            style: const TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(config.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${config.baseUrl}\n'
          '删除于 ${_formatDate(deletedAt)} · '
          '${remaining <= 0 ? '即将清除' : '$remaining 天后自动清除'}',
          style: TextStyle(fontSize: 12, color: secondary, height: 1.5),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => _restore(config),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('恢复'),
            ),
            IconButton(
              icon: Icon(Icons.delete_forever_outlined,
                  color: AppColors.error.withValues(alpha: 0.8)),
              tooltip: '彻底删除',
              onPressed: _busy ? null : () => _purge(config),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
