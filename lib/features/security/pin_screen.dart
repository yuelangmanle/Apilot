import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../shared/theme/color_scheme.dart';
import 'app_lock_controller.dart';
import 'biometric_service.dart';

/// 锁屏门：锁定时直接替换应用首页（同一 MaterialApp 内 home swap）。
/// 锁屏是唯一路由且禁止返回键离开——不存在被"点空白"绕过、看到或
/// 操作内页的可能；生物识别弹窗只是浮在锁屏之上的系统 UI。
class LockGate extends StatelessWidget {
  final Widget child;

  const LockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    if (lock.enabled && lock.locked) {
      return const PinScreen();
    }
    return child;
  }
}

/// PIN 输入：解锁与首次设置共用（[mode] 区分）。
class PinScreen extends StatefulWidget {
  final PinScreenMode mode;

  const PinScreen({super.key, this.mode = PinScreenMode.unlock});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

enum PinScreenMode { unlock, setFirst, setConfirm }

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  String _firstPin = '';
  late PinScreenMode _mode = widget.mode;
  bool _biometricAvailable = false;
  bool _biometricPrompted = false;
  late final AnimationController _shakeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));

  static const _length = 4;

  void _shake() {
    _shakeController.forward(from: 0);
  }

  late final _LifecycleHook _lifecycleHook = _LifecycleHook(_onResumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleHook);
    _prepareBiometric();
  }

  /// 从后台返回时：只要还处于锁定，就重新弹出生物识别。
  /// 修复"取消指纹→切桌面→回来不再验证"的漏洞。
  void _onResumed() {
    if (!mounted) return;
    final lock = context.read<AppLockController>();
    if (lock.enabled && lock.locked) {
      _biometricPrompted = false;
      _prepareBiometric();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleHook);
    _shakeController.dispose();
    super.dispose();
  }

  /// 解锁模式下：设备支持且用户开启了生物识别时，进入页面自动弹一次
  /// 系统指纹/面容；取消后仍可用 PIN。
  Future<void> _prepareBiometric() async {
    if (_mode != PinScreenMode.unlock) return;
    final lock = context.read<AppLockController>();
    if (!lock.biometricEnabled) return;
    final available = await BiometricService.isAvailable();
    if (!mounted || !available) return;
    setState(() => _biometricAvailable = true);
    if (_biometricPrompted) return;
    _biometricPrompted = true;
    await _authenticateWithBiometrics();
  }

  Future<void> _authenticateWithBiometrics() async {
    final lock = context.read<AppLockController>();
    final ok = await lock.authenticateAndUnlock();
    if (!mounted || !ok) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(true);
  }

  void _append(String digit) {
    if (_pin.length >= _length) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == _length) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final lock = context.read<AppLockController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    switch (_mode) {
      case PinScreenMode.unlock:
        final ok = await lock.unlock(_pin);
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _pin = '';
            _error = 'PIN 不正确';
          });
          HapticFeedback.vibrate();
          _shake();
        } else {
          // 锁屏态是 LockGate 的唯一路由（不能 pop）；从设置页进入时
          // 则返回设置页并告知验证成功。
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop(true);
        }
        break;
      case PinScreenMode.setFirst:
        _firstPin = _pin;
        setState(() {
          _mode = PinScreenMode.setConfirm;
          _pin = '';
          _error = null;
        });
        break;
      case PinScreenMode.setConfirm:
        if (_pin != _firstPin) {
          setState(() {
            _mode = PinScreenMode.setFirst;
            _pin = '';
            _error = '两次输入不一致，请重新设置';
          });
          HapticFeedback.vibrate();
          return;
        }
        try {
          await lock.enable(_firstPin);
          if (!mounted) return;
          navigator.pop(true);
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    final title = switch (_mode) {
      PinScreenMode.unlock => '输入 PIN 解锁',
      PinScreenMode.setFirst => '设置应用锁 PIN',
      PinScreenMode.setConfirm => '再次输入确认',
    };
    return PopScope(
      // 锁屏是唯一的路由：返回键不允许离开。
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (lock.loadFailed)
                Container(
                  width: double.infinity,
                  color: AppColors.error,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Text(
                    '锁设置读取失败，已进入保护态。请输入 PIN；若遗忘请清除应用数据重置。',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              const Spacer(flex: 2),
              const Icon(Icons.lock_outline,
                  size: 44, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18)),
              if (_mode == PinScreenMode.unlock && _biometricAvailable) ...[
                const SizedBox(height: 16),
                IconButton.filledTonal(
                  onPressed: _authenticateWithBiometrics,
                  icon: const Icon(Icons.fingerprint, size: 32),
                  iconSize: 32,
                  tooltip: '使用指纹或面容解锁',
                ),
                const SizedBox(height: 4),
                const Text('或使用下方 PIN 解锁',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  final offset = _shakeController.isAnimating
                      ? math.sin(_shakeController.value * math.pi * 4) * 8
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(offset, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_length, (index) {
                    final filled = index < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.15),
                      ),
                    );
                  }),
                ),
              ),
              const Spacer(flex: 2),
              _buildPad(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPad(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Column(
        children: keys
            .map((row) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: row.map((key) {
                    if (key.isEmpty) {
                      return const SizedBox(width: 72, height: 64);
                    }
                    if (key == '⌫') {
                      return Semantics(
                        label: '删除一位',
                        button: true,
                        child: _padButton(
                          const Icon(Icons.backspace_outlined,
                              size: 22, color: AppColors.textSecondary),
                          onTap: () {
                            if (_pin.isNotEmpty) {
                              setState(() =>
                                  _pin = _pin.substring(0, _pin.length - 1));
                            }
                          },
                        ),
                      );
                    }
                    return _padButton(
                      Text(key,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w500)),
                      onTap: () => _append(key),
                    );
                  }).toList(),
                ))
            .toList(),
      ),
    );
  }

  Widget _padButton(Widget child, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 64,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// 轻量生命周期观察者：把 resumed 事件转发给回调。
class _LifecycleHook with WidgetsBindingObserver {
  final VoidCallback onResumed;
  _LifecycleHook(this.onResumed);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
