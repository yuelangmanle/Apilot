import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/api_config.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../api_testing/screens/test_screen.dart';

class ApiCard extends StatelessWidget {
  final ApiConfig api;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;

  const ApiCard({
    super.key,
    required this.api,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondaryColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Dismissible(
      key: Key(api.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.star, color: Colors.white),
          SizedBox(width: 8),
          Text('收藏', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(width: 8),
          Icon(Icons.delete, color: Colors.white),
        ]),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onFavoriteToggle();
          return false;
        } else {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('确认删除'),
              content: Text('确定要删除 ${api.name} 吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                TextButton(onPressed: () { Navigator.pop(context, true); onDelete(); }, child: const Text('删除', style: TextStyle(color: Colors.red))),
              ],
            ),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(api.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))),
                    IconButton(
                      icon: Icon(api.isFavorite ? Icons.star : Icons.star_border,
                        color: api.isFavorite ? AppColors.warning : secondaryColor, size: 22),
                      onPressed: onFavoriteToggle,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCopyableRow(context, api.baseUrl, Icons.link, secondaryColor, 'URL已复制'),
                if (api.models.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildCopyableRow(context, '模型: ${api.models.join(', ')}', Icons.smart_toy, secondaryColor, '模型列表已复制', copyText: api.models.join(', ')),
                ],
                const SizedBox(height: 4),
                _buildCopyableRow(context, 'Key: ${_maskApiKey(api.apiKey)}', Icons.key, secondaryColor, 'API Key已复制', copyText: api.apiKey),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (api.group != null) _buildTag(api.group!, AppColors.primary),
                    _buildTag(api.environment, AppColors.secondary),
                    if (api.models.length > 3)
                      _buildTag('${api.models.length}个模型', AppColors.accent),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('测试', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => TestScreen(apiConfig: api)));
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

  Widget _buildCopyableRow(BuildContext context, String text, IconData icon, Color color, String snackMsg, {String? copyText}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: copyText ?? text));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(snackMsg), duration: const Duration(seconds: 1)));
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.copy, size: 16, color: AppColors.primary)),
        ),
      ],
    );
  }

  String _maskApiKey(String apiKey) {
    if (apiKey.length <= 8) return '****';
    return '${apiKey.substring(0, 4)}****${apiKey.substring(apiKey.length - 4)}';
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
