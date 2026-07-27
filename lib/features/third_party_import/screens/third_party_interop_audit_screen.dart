import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/api_interop_audit.dart';
import '../../../core/services/api_profile_registry.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/theme/color_scheme.dart';

class ThirdPartyInteropAuditScreen extends StatefulWidget {
  const ThirdPartyInteropAuditScreen({super.key});

  @override
  State<ThirdPartyInteropAuditScreen> createState() =>
      _ThirdPartyInteropAuditScreenState();
}

class _ThirdPartyInteropAuditScreenState
    extends State<ThirdPartyInteropAuditScreen> {
  final DatabaseService _databaseService = DatabaseService();
  late Future<List<ApiInteropAudit>> _audits;

  @override
  void initState() {
    super.initState();
    _audits = _databaseService.getInteropAudits();
  }

  Future<void> _reload() async {
    setState(() {
      _audits = _databaseService.getInteropAudits();
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除互操作记录'),
        content: const Text('只会删除本地授权和导入记录，不会删除 API 方案。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _databaseService.clearInteropAudits();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('第三方交互记录'),
        actions: [
          IconButton(
            tooltip: '清除记录',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<ApiInteropAudit>>(
        future: _audits,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final audits = snapshot.data ?? const <ApiInteropAudit>[];
          if (audits.isEmpty) {
            return const Center(
              child: Text('还没有第三方导入或授权记录'),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: audits.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _AuditTile(audit: audits[index]),
            ),
          );
        },
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final ApiInteropAudit audit;

  const _AuditTile({required this.audit});

  @override
  Widget build(BuildContext context) {
    final profile = ApiProfileRegistry.resolve(
      baseUrl: '',
      providerId: audit.providerId,
      protocolId: audit.protocolId,
    );
    final isOutbound = audit.direction == ApiInteropAuditDirection.outbound;
    final timestamp = DateFormat('yyyy-MM-dd HH:mm').format(audit.createdAt);
    return Card(
      child: ListTile(
        leading: Icon(
          isOutbound ? Icons.outbox_outlined : Icons.move_to_inbox_outlined,
          color: isOutbound ? AppColors.warning : AppColors.primary,
        ),
        title: Text(audit.apiConfigName),
        subtitle: Text(
          '${isOutbound ? '授权给' : '导入自'} ${audit.sourceName ?? '未知来源'}\n'
          '${profile.providerDisplayName} · ${audit.selectedModel ?? '未设置默认模型'} · $timestamp',
        ),
        isThreeLine: true,
        trailing: audit.apiKeyShared
            ? Tooltip(
                message: isOutbound ? '此次已授权 API Key' : '此次导入包含 API Key',
                child: const Icon(Icons.key, color: AppColors.warning),
              )
            : null,
      ),
    );
  }
}
