class QrScannerError {
  final String message;
  final bool canRetry;
  final bool canOpenSettings;

  const QrScannerError._({
    required this.message,
    required this.canRetry,
    required this.canOpenSettings,
  });

  factory QrScannerError.cancelled() => const QrScannerError._(
        message: '已取消扫码',
        canRetry: true,
        canOpenSettings: false,
      );

  factory QrScannerError.invalidPayload() => const QrScannerError._(
        message: '二维码或 IP 地址格式不正确',
        canRetry: true,
        canOpenSettings: false,
      );

  factory QrScannerError.fromPlatformCode(String code) {
    switch (code) {
      case 'camera_permission_denied':
        return const QrScannerError._(
          message: '需要相机权限才能扫描二维码',
          canRetry: true,
          canOpenSettings: false,
        );
      case 'camera_permission_permanently_denied':
        return const QrScannerError._(
          message: '相机权限已被系统拒绝，请在系统设置中允许 Apilot 使用相机',
          canRetry: false,
          canOpenSettings: true,
        );
      default:
        return const QrScannerError._(
          message: '无法打开扫码器，请改用手动输入',
          canRetry: true,
          canOpenSettings: false,
        );
    }
  }
}
