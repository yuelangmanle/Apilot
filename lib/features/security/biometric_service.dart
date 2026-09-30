import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';

/// 系统生物识别（指纹/面容/Touch ID）封装。
/// 平台门控：Android/iOS/macOS 支持；Windows 与其他平台回退 PIN。
class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// 当前平台是否具备可用的生物识别硬件与已录入凭据。
  static Future<bool> isAvailable() async {
    try {
      if (Platform.isWindows || Platform.isLinux) return false;
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck;
    } catch (e) {
      debugPrint('[Biometric] 可用性检测失败: $e');
      return false;
    }
  }

  /// 弹出系统指纹/面容对话框。用户取消或失败返回 false。
  static Future<bool> authenticate() async {
    try {
      if (Platform.isWindows || Platform.isLinux) return false;
      return await _auth.authenticate(
        localizedReason: '验证指纹或面容以解锁 Apilot',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('[Biometric] 认证失败: $e');
      return false;
    }
  }
}
