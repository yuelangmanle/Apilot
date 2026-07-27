import 'package:flutter/material.dart';

import '../../../core/services/update_service.dart';
import '../../../shared/theme/color_scheme.dart';

class ReleaseHistoryScreen extends StatefulWidget {
  const ReleaseHistoryScreen({super.key});

  @override
  State<ReleaseHistoryScreen> createState() => _ReleaseHistoryScreenState();
}

class _ReleaseHistoryScreenState extends State<ReleaseHistoryScreen> {
  final UpdateService _updateService = UpdateService();
  late Future<List<ReleaseInfo>> _history;

  @override
  void initState() {
    super.initState();
    _history = _updateService.getReleaseHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _history = _updateService.getReleaseHistory();
    });
    await _history;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
      body: FutureBuilder<List<ReleaseInfo>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HistoryError(onRetry: _reload);
          }

          final history = snapshot.data ?? const <ReleaseInfo>[];
          if (history.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                children: const [
                  SizedBox(height: 240),
                  Center(child: Text('暂时没有可显示的更新日志')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ReleaseCard(
                release: history[index],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  final ReleaseInfo release;

  const _ReleaseCard({required this.release});

  @override
  Widget build(BuildContext context) {
    final notes = release.releaseNotes.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'v${release.version}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  _formatDate(release.publishedAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            SelectableText(
              notes.isEmpty ? '此版本没有发布说明。' : notes,
              style: const TextStyle(height: 1.45),
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

class _HistoryError extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _HistoryError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.warning),
            const SizedBox(height: 12),
            const Text('无法加载更新日志'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
