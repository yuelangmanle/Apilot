import 'package:api_manager/features/security/app_lock_controller.dart';
import 'package:api_manager/features/security/pin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归测试：锁屏 PIN 校验必须在"没有 Navigator 祖先"时也能进行。
///
/// 曾经的 bug：锁屏 PinScreen 挂在 LockGate（MaterialApp.builder 覆盖层）里，
/// 而 _submit() 开头无条件调用 `Navigator.of(context)` —— 覆盖层在 Navigator
/// 之外，这一行同步抛错，PIN 校验根本没开始：表现为 4 个点填满后界面毫无反应
/// （没有转圈、没有报错、永远进不去）。
/// 测试用快速派生：真实 PBKDF2 跑在独立 isolate，widget 测试的假时钟
/// 不会驱动它，会挂死。生产路径由 hashPinAsync 覆盖（另有单元测试）。
Future<String> _fastHasher(String pin, String salt) async => 'h:$salt:$pin';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('锁屏覆盖层里输入正确 PIN 能解锁（无 Navigator 祖先）',
      (tester) async {
    final lock = AppLockController(hasher: _fastHasher);
    await lock.enable('1234');
    // enable 之后处于锁定态（模拟启动时自动上锁）。
    expect(lock.locked, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppLockController>.value(
        value: lock,
        child: MaterialApp(
          // builder 包裹 Navigator：覆盖层里没有 Navigator 祖先，
          // 与线上锁屏的挂载方式一致。
          builder: (context, child) => LockGate(lockChild: child),
          home: const Scaffold(
            body: Center(child: Text('已解锁的应用内容')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 锁屏可见、应用内容不可见。
    expect(find.text('输入 PIN 解锁'), findsOneWidget);
    expect(find.text('已解锁的应用内容'), findsNothing);

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(lock.locked, isFalse,
        reason: '输入正确 PIN 后必须解锁——_submit 不允许在校验前抛错中断');
    expect(find.text('输入 PIN 解锁'), findsNothing);
    expect(find.text('已解锁的应用内容'), findsOneWidget);
    lock.dispose();
  });

  testWidgets('锁屏覆盖层里输入错误 PIN 会清空并提示，而不是卡死',
      (tester) async {
    final lock = AppLockController(hasher: _fastHasher);
    await lock.enable('1234');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppLockController>.value(
        value: lock,
        child: MaterialApp(
          builder: (context, child) => LockGate(lockChild: child),
          home: const Scaffold(body: Center(child: Text('已解锁的应用内容'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('9'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(lock.locked, isTrue, reason: '错误 PIN 不应解锁');
    expect(find.text('PIN 不正确'), findsOneWidget,
        reason: '错误 PIN 必须有可见反馈，不能静默卡住');
    expect(find.text('已解锁的应用内容'), findsNothing);
    lock.dispose();
  });
}
