import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/color_scheme.dart';
import '../utils/qr_sync_payload.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  static const MethodChannel _scannerChannel = MethodChannel(
    'com.apilot/qr_scanner',
  );

  final _ipController = TextEditingController();
  bool _useManualInput = false;
  bool _isScanning = false;
  String? _scannerError;

  bool get _scannerSupported => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_scannerSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startQrScan());
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
        actions: [
          TextButton.icon(
            onPressed: _toggleInputMode,
            icon: Icon(
              _useManualInput ? Icons.qr_code_scanner : Icons.edit,
              color: Colors.white,
            ),
            label: Text(
              _useManualInput ? '扫码' : '手动',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _useManualInput || !_scannerSupported
          ? _buildManualInput()
          : _buildScannerLauncher(),
    );
  }

  void _toggleInputMode() {
    setState(() => _useManualInput = !_useManualInput);
    if (!_useManualInput) _startQrScan();
  }

  Widget _buildScannerLauncher() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _scannerError == null
                        ? Icons.qr_code_scanner
                        : Icons.camera_alt_outlined,
                    size: 56,
                    color: _scannerError == null
                        ? AppColors.primary
                        : AppColors.warning,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isScanning ? '正在打开扫码器...' : '扫描同步二维码',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_scannerError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _scannerError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_isScanning)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton.icon(
                      onPressed: _startQrScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('打开扫码器'),
                    ),
                ],
              ),
            ),
          ),
        ),
        _buildScannerTips(),
      ],
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
                      Text(
                        '输入设备IP地址',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '在对方设备的“同步”页面可以看到IP地址',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
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
                '1. 确保对方设备的同步页面保持打开\n'
                '2. 在对方设备的“同步”页面查看IP地址或二维码\n'
                '3. 连接成功后可选择发送、接收或双向同步',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startQrScan() async {
    if (!_scannerSupported || _isScanning) return;
    setState(() {
      _isScanning = true;
      _scannerError = null;
    });

    try {
      final rawValue = await _scannerChannel.invokeMethod<String>('scanQrCode');
      if (!mounted) return;
      if (rawValue == null || rawValue.trim().isEmpty) {
        setState(() => _scannerError = '已取消扫码');
        return;
      }
      _connectByText(rawValue);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _scannerError = e.message?.trim().isNotEmpty == true
            ? e.message!
            : '无法打开扫码器，请改用手动输入';
      });
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _connectByText(String text) {
    final ip = extractSyncIp(text.trim());
    if (ip == null) {
      if (mounted) {
        setState(() => _scannerError = '二维码或 IP 地址格式不正确');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('二维码或IP地址格式不正确'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    Navigator.pop(context, ip);
  }
}
