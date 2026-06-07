import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../shared/theme/color_scheme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _ipController = TextEditingController();
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _useManualInput = false;
  bool _handledScan = false;

  @override
  void dispose() {
    _scannerController.dispose();
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
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _useManualInput = !_useManualInput),
            icon: Icon(_useManualInput ? Icons.qr_code_scanner : Icons.edit, color: Colors.white),
            label: Text(_useManualInput ? '扫码' : '手动', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _useManualInput || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
          ? _buildManualInput()
          : Column(
              children: [
                Expanded(
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: _handleBarcodeCapture,
                    errorBuilder: (context, error) {
                      return _buildScannerError(error.toString());
                    },
                  ),
                ),
                _buildScannerTips(),
              ],
            ),
    );
  }

  Widget _buildScannerError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 56, color: AppColors.warning),
            const SizedBox(height: 16),
            const Text('无法打开摄像头', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => setState(() => _useManualInput = true),
              icon: const Icon(Icons.keyboard),
              label: const Text('改用手动输入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerTips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Text(
        '请扫描对方“设备同步”页面里的二维码。扫码失败时，可点右上角“手动”输入 IP。',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildManualInput() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.wifi, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('输入设备IP地址', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('在对方设备的“同步”页面可以看到IP地址', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                      onPressed: () => _connectByText(_ipController.text),
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
          Card(
            color: AppColors.primary.withValues(alpha: 0.05),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '连接提示\n'
                '1. 确保两台设备在同一WiFi网络下\n'
                '2. 在对方设备的“同步”页面查看IP地址或二维码\n'
                '3. 连接成功后可选择发送、接收或双向同步',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBarcodeCapture(BarcodeCapture capture) {
    if (_handledScan) return;
    final rawValue = capture.barcodes.where((barcode) => barcode.rawValue != null).map((barcode) => barcode.rawValue!).firstOrNull;
    if (rawValue == null) return;
    _handledScan = true;
    _connectByText(rawValue);
  }

  void _connectByText(String text) {
    final ip = _extractIP(text.trim());
    if (ip == null) {
      _handledScan = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码或IP地址格式不正确'), backgroundColor: AppColors.error),
      );
      return;
    }
    Navigator.pop(context, ip);
  }

  String? _extractIP(String value) {
    final firstField = value.split('|').first.trim();
    final uri = Uri.tryParse(firstField);
    final candidate = uri != null && uri.hasScheme ? uri.host : firstField;
    final parts = candidate.split('.');
    if (parts.length != 4) return null;
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) return null;
    }
    return candidate;
  }
}
