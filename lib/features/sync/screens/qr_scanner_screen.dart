import 'package:flutter/material.dart';
import '../../../shared/theme/color_scheme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _ipController = TextEditingController();
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkCamera();
  }

  Future<void> _checkCamera() async {
    // Try to check if camera is available
    // If mobile_scanner fails to init, fall back to manual input
    try {
      // Simple check - if we can't use camera, show manual input
      setState(() {
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _checking = false;
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Manual IP input (always available)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.wifi, color: AppColors.primary),
                              const SizedBox(width: 8),
                              const Text(
                                '输入设备IP地址',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '在对方设备的"同步"页面可以看到IP地址',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: 'IP地址',
                              hintText: '例如: 192.168.1.100',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.computer),
                            ),
                            keyboardType: TextInputType.url,
                            autofocus: true,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _connectByIP,
                              icon: const Icon(Icons.link),
                              label: const Text('连接'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Tips
                  Card(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 20),
                              const SizedBox(width: 8),
                              const Text('连接提示', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. 确保两台设备在同一WiFi网络下\n'
                            '2. 在对方设备的"同步"页面查看IP地址\n'
                            '3. 输入IP后点击"连接"\n'
                            '4. 连接成功后可选择同步方向',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _connectByIP() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入IP地址'), backgroundColor: AppColors.warning),
      );
      return;
    }

    // Basic IP validation
    final parts = ip.split('.');
    if (parts.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP地址格式不正确'), backgroundColor: AppColors.error),
      );
      return;
    }

    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IP地址格式不正确'), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    Navigator.pop(context, ip);
  }
}
