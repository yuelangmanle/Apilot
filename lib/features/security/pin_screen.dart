import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../shared/theme/color_scheme.dart';
import '../../../shared/theme/app_theme.dart';
import 'app_lock_controller.dart';

/// 锁屏门：锁定时遮住整个应用，输入正确 PIN 后放行。
class LockGate extends StatelessWidget {
  final Widget child;

  const LockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    if (!lock.initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (lock.enabled && lock.locked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const PinScreen(),
      );
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

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String? _error;
  String _firstPin = '';
  late PinScreenMode _mode = widget.mode;

  static const _length = 4;

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
    final title = switch (_mode) {
      PinScreenMode.unlock => '输入 PIN 解锁',
      PinScreenMode.setFirst => '设置应用锁 PIN',
      PinScreenMode.setConfirm => '再次输入确认',
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const Icon(Icons.lock_outline, size: 44, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 24),
            Row(
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
            const Spacer(flex: 2),
            _buildPad(context),
            const SizedBox(height: 24),
          ],
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
                    if (key.isEmpty) return const SizedBox(width: 72, height: 64);
                    if (key == '⌫') {
                      return _padButton(
                        const Icon(Icons.backspace_outlined,
                            size: 22, color: AppColors.textSecondary),
                        onTap: () {
                          if (_pin.isNotEmpty) {
                            setState(
                                () => _pin = _pin.substring(0, _pin.length - 1));
                          }
                        },
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