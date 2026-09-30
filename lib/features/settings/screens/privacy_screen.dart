import 'package:flutter/material.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/widgets/responsive_layout.dart';

/// 数据与安全说明页：把"你的密钥存在哪里、谁能看到"用产品语言讲清楚。
/// 信任要主动展示，不是藏在代码里。
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = ResponsiveLayout.isWide(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(context, Icons.enhanced_encryption, '密钥加密存储',
            '所有 API Key 使用 Fernet（AES-CBC + HMAC-SHA256）加密后写入本地数据库，'
                '加密主密钥保存在系统安全区（Android Keystore / 系统安全存储），'
                '应用本身也无法在不解锁系统密钥的情况下读出明文。'),
        _card(context, Icons.computer, '数据只留在本机',
            '你的配置、请求历史、体检结果全部保存在本机数据库。'
                'Apilot 没有账号体系、没有服务器，不会把任何配置或密钥上传到我们的服务器——因为我们没有这样的服务器。'),
        _card(context, Icons.wifi_lock, '同步需要双方确认',
            '局域网与蓝牙同步都必须由接收方在屏幕上明确点击"允许"才会执行；'
                '扫码配对的设备之间配置走加密通道，网络抓包只能看到密文。'
                '手动输入 IP 的连接使用明文传输，请在可信网络下使用。'),
        _card(context, Icons.timer_off, '剪贴板自动清除',
            '复制 API Key 后，剪贴板会在 60 秒后自动清空（期间剪贴板内容未被覆盖时），'
                '降低被其他应用读取的风险。'),
        _card(context, Icons.history_toggle_off, '历史有上限、响应有大小限制',
            '请求历史最多保留最近 500 条，超大响应不会整包入库，数据库不会无限膨胀。'),
        _card(context, Icons.code, '开源可审计',
            'Apilot 是开源软件，上述每一句话都对应可以复查的代码：'
                'github.com/yuelangmanle/Apilot'),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '备份文件是唯一以明文包含密钥的产物（需要你自己选择保存位置），导出前应用会再次提醒。',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('数据与安全')),
      body: isWide ? CenteredContent(maxWidth: 640, child: content) : content,
    );
  }

  Widget _card(
      BuildContext context, IconData icon, String title, String body) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body,
                style: TextStyle(fontSize: 13, height: 1.6, color: secondary)),
          ],
        ),
      ),
    );
  }
}
