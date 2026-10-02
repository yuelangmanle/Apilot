import 'dart:io';

import 'package:flutter/foundation.dart';

/// 设备能力探测：用于本地模型的量化版本推荐。
class DeviceCapabilities {
  final int ramMb;
  final int cpuCores;
  final String platform;
  final bool isAndroid;

  const DeviceCapabilities({
    required this.ramMb,
    required this.cpuCores,
    required this.platform,
    required this.isAndroid,
  });

  /// 探测当前设备。RAM 读不到时按平台给保守估计。
  static Future<DeviceCapabilities> detect() async {
    return DeviceCapabilities(
      ramMb: await _detectRamMb(),
      cpuCores: Platform.numberOfProcessors,
      platform: Platform.operatingSystem,
      isAndroid: Platform.isAndroid,
    );
  }

  /// 一行摘要（用于 AI 提示词与界面展示）。
  String get summary =>
      '设备：$platform，内存约 ${(ramMb / 1024).toStringAsFixed(1)}GB，'
      '$cpuCores 核 CPU';

  static Future<int> _detectRamMb() async {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        // /proc/meminfo: MemTotal:  16384000 kB
        final meminfo = File('/proc/meminfo');
        if (meminfo.existsSync()) {
          for (final line in meminfo.readAsLinesSync()) {
            if (line.startsWith('MemTotal:')) {
              final kb = int.tryParse(
                  RegExp(r'\d+').firstMatch(line)?.group(0) ?? '');
              if (kb != null && kb > 0) return kb ~/ 1024;
            }
          }
        }
      }
      if (Platform.isMacOS) {
        final result = Process.runSync('sysctl', ['-n', 'hw.memsize']);
        final bytes = int.tryParse('${result.stdout}'.trim());
        if (bytes != null && bytes > 0) return bytes ~/ (1024 * 1024);
      }
      if (Platform.isWindows) {
        final result = Process.runSync('wmic', [
          'ComputerSystem',
          'get',
          'TotalPhysicalMemory',
        ]);
        final bytes = int.tryParse(
            RegExp(r'\d+').firstMatch('${result.stdout}')?.group(0) ?? '');
        if (bytes != null && bytes > 0) return bytes ~/ (1024 * 1024);
      }
    } catch (e) {
      debugPrint('[Device] 内存探测失败: $e');
    }
    // 保守估计：按平台常见值。
    if (Platform.isAndroid || Platform.isIOS) return 8192;
    if (Platform.isMacOS) return 16384;
    return 8192;
  }
}
