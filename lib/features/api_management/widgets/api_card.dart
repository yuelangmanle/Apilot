import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/api_config.dart';
import '../../../core/services/api_profile_registry.dart';
import '../../../core/services/health_check_service.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/utils/clipboard_privacy.dart';
import '../../api_testing/screens/test_screen.dart';

class ApiCard extends StatelessWidget {
  final ApiConfig api;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;
  final HealthCheckResult? health;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  const ApiCard({
    super.key,
    required this.api,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
    this.health,
    this.selectMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondaryColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final profile = ApiProfileRegistry.resolve(
      baseUrl: api.baseUrl,
      providerId: api.providerId,
      protocolId: api.protocolId,
    );
    final selectedModel =
        api.selectedModel ?? (api.models.isEmpty ? null : api.models.first);

    return Dismissible(
      key: Key(api.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
            color: AppColors.warning, borderRadius: BorderRadius.circular(12)),
        // 琥珀底上白字对比度只有 1.6:1，改用深色文字。
        child: const Row(children: [
          Icon(Icons.star, color: Colors.black87),
          SizedBox(width: 8),
          Text('收藏',
              style: TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.bold)),
        ]),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
            color: AppColors.error, borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('删除',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          Icon(Icons.delete, color: Colors.white),
        ]),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavoriteToggle();
          return false;
        }
        // 左滑删除必须先确认：取消时卡片弹回原位，不会先消失。
        return await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('移入回收站？'),
                content: Text('「${api.name}」将移入回收站，保留期内可随时恢复。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('移入回收站',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ) ==
            true;
      },
      // 关键：确认后卡片被移除时**必须**执行真正的删除。
      // 此前缺失此回调，导致"卡片消失但数据库没改"，重启后配置复活、
      // 回收站为空——这是回收站长期异常的真正根因。
      onDismissed: (direction) {
        onDelete();
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: selected && selectMode
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.primary, width: 2),
              )
            : null,
        child: InkWell(
          onTap: selectMode ? onSelectToggle : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selectMode)
                      GestureDetector(
                        onTap: onSelectToggle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 22,
                          ),
                        ),
                      ),
                    Expanded(
                        child: Hero(
                          tag: 'api-name-${api.id}',
                          child: Text(api.name,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor)),
                        )),
                    IconButton(
                      icon: Icon(
                          api.isFavorite ? Icons.star : Icons.star_border,
                          color: api.isFavorite
                              ? AppColors.warning
                              : secondaryColor,
                          size: 22),
                      onPressed: onFavoriteToggle,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCopyableRow(
                    context,
                    '${profile.providerDisplayName} · ${profile.protocolDisplayName}',
                    Icons.hub,
                    secondaryColor,
                    '协议已复制',
                    copyText: '${profile.providerId}:${profile.protocolId}'),
                if (selectedModel != null) ...[
                  const SizedBox(height: 4),
                  _buildCopyableRow(context, '默认模型: $selectedModel',
                      Icons.smart_toy_outlined, secondaryColor, '默认模型已复制',
                      copyText: selectedModel),
                ],
                _buildCopyableRow(
                    context, api.baseUrl, Icons.link, secondaryColor, 'URL已复制'),
                if (api.models.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildCopyableRow(context, '模型: ${api.models.join(', ')}',
                      Icons.smart_toy, secondaryColor, '模型列表已复制',
                      copyText: api.models.join(', ')),
                ],
                const SizedBox(height: 4),
                _buildCopyableRow(context, 'Key: ${_maskApiKey(api.apiKey)}',
                    Icons.key, secondaryColor, 'API Key已复制',
                    copyText: api.apiKey),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (api.group != null)
                      _buildTag(api.group!, AppColors.primary,
                          textColor: AppColors.primaryText),
                    _buildTag(api.environment, AppColors.secondary,
                        textColor: AppColors.secondaryText),
                    if (api.models.length > 3)
                      _buildTag('${api.models.length}个模型', AppColors.accent,
                          textColor: AppColors.accentText),
                    _buildHealthTag(),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('测试', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    TestScreen(apiConfig: api)));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCopyableRow(BuildContext context, String text, IconData icon,
      Color color, String snackMsg,
      {String? copyText}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
        InkWell(
          onTap: () {
            if (copyText != null && snackMsg.contains('Key')) {
              // Key 复制走隐私剪贴板：60 秒后自动清空。
              ClipboardPrivacy.copySensitive(copyText);
            } else {
              Clipboard.setData(ClipboardData(text: copyText ?? text));
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(snackMsg == 'API Key已复制'
                    ? '$snackMsg（60秒后自动清空剪贴板）'
                    : snackMsg),
                duration: const Duration(seconds: 1)));
          },
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, size: 16, color: AppColors.primary)),
        ),
      ],
    );
  }

  Widget _buildHealthTag() {
    if (health == null) return const SizedBox.shrink();
    final (Color color, String text) = switch (health!.status) {
      KeyHealthStatus.ok => (AppColors.success, '正常'),
      KeyHealthStatus.authFailed => (AppColors.error, '失效'),
      KeyHealthStatus.unreachable => (AppColors.warning, '失联'),
      KeyHealthStatus.emptyOk => (AppColors.secondaryText, '可达'),
      KeyHealthStatus.unknown => (AppColors.textSecondary, '未知'),
    };
    return _buildTag(text, color, textColor: color);
  }

  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}';
  }

  Widget _buildTag(String text, Color color, {Color? textColor}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              // 浅色底配深色文字，保证可读性。
              color: textColor ?? color,
              fontWeight: FontWeight.w500)),
    );
  }
}
