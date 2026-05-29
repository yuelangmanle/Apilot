import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../shared/theme/color_scheme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    try {
      _controller = MobileScannerController();
    } catch (e) {
      debugPrint('Failed to init mobile scanner: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;

    _isProcessing = true;

    // Try to extract IP from QR code
    // QR format: expected to be an IP address or a URL containing IP
    String ip = value.trim();

    // If it's a URL like http://192.168.1.1:45679, extract the host
    if (ip.startsWith('http://') || ip.startsWith('https://')) {
      try {
        final uri = Uri.parse(ip);
        ip = uri.host;
      } catch (_) {}
    }

    // Remove port if present
    if (ip.contains(':')) {
      final parts = ip.split(':');
      ip = parts[0];
    }

    if (mounted) {
      Navigator.pop(context, ip);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_controller != null)
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller?.toggleTorch(),
              tooltip: '闪光灯',
            ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _controller == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.white54),
                  const SizedBox(height: 16),
                  const Text(
                    '无法启动摄像头',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '请检查摄像头权限设置',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回手动输入'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                MobileScanner(
                  controller: _controller!,
                  onDetect: _onDetect,
                ),
                // Scan overlay
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '将二维码放入框内自动扫描',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
