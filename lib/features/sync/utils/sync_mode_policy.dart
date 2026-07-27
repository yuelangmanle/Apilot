enum SyncMode {
  wifi,
  bluetooth,
}

class SyncModePolicy {
  static bool shouldRunWifiDiscovery(SyncMode mode) => mode == SyncMode.wifi;

  static String title(SyncMode mode) {
    switch (mode) {
      case SyncMode.wifi:
        return 'WiFi 局域网同步';
      case SyncMode.bluetooth:
        return '蓝牙直接传输';
    }
  }

  static String emptyStateMessage(SyncMode mode) {
    switch (mode) {
      case SyncMode.wifi:
        return '请扫描对方二维码或手动输入 IP 连接\n确保两台设备在同一 WiFi 下';
      case SyncMode.bluetooth:
        return '请点击“蓝牙发现”查找附近设备\n对方也需要打开设备同步页面';
    }
  }

  static String bluetoothDiscoveryStatus({
    required int discovered,
    required int added,
  }) {
    if (discovered == 0) {
      return '蓝牙未发现设备，请确认对方已打开蓝牙同步发现';
    }
    return '蓝牙发现 $discovered 台设备，新增/更新 $added 台';
  }
}
