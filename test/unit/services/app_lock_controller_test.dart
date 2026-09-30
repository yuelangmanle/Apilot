import 'package:api_manager/features/security/app_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLockController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts unlocked when lock was never enabled', () async {
      final controller = AppLockController();
      await Future<void>.delayed(Duration.zero);
      expect(controller.enabled, isFalse);
      expect(controller.locked, isFalse);
      expect(controller.biometricEnabled, isFalse);
      controller.dispose();
    });

    test('enable sets lock and rejects short pins', () async {
      final controller = AppLockController();
      await Future<void>.delayed(Duration.zero);

      expect(() => controller.enable('123'), throwsStateError);
      await controller.enable('1234');
      expect(controller.enabled, isTrue);
      expect(controller.locked, isTrue);
      controller.dispose();
    });

    test('unlock only accepts the configured pin', () async {
      final controller = AppLockController();
      await Future<void>.delayed(Duration.zero);
      await controller.enable('9876');

      expect(await controller.unlock('0000'), isFalse);
      expect(controller.locked, isTrue);
      expect(await controller.unlock('9876'), isTrue);
      expect(controller.locked, isFalse);
      controller.dispose();
    });

    test('biometric unlock only works when both flags are on', () async {
      final controller = AppLockController();
      await Future<void>.delayed(Duration.zero);
      await controller.enable('1234');
      // 生物识别未开启：不应放行。
      controller.unlockViaBiometric();
      expect(controller.locked, isTrue);

      await controller.setBiometricEnabled(true);
      expect(controller.biometricEnabled, isTrue);
      controller.unlockViaBiometric();
      expect(controller.locked, isFalse);
      controller.dispose();
    });

    test('disable clears biometric flag and pin hash', () async {
      final controller = AppLockController();
      await Future<void>.delayed(Duration.zero);
      await controller.enable('1234');
      await controller.setBiometricEnabled(true);
      expect(await controller.unlock('1234'), isTrue);

      await controller.disable();
      expect(controller.enabled, isFalse);
      expect(controller.biometricEnabled, isFalse);
      expect(await controller.isPinSet(), isFalse);
      controller.dispose();
    });

    test('hashPin is salted and deterministic', () {
      expect(AppLockController.hashPin('2468', 's1'),
          AppLockController.hashPin('2468', 's1'));
      expect(AppLockController.hashPin('2468', 's1'),
          isNot(AppLockController.hashPin('2468', 's2')));
    });
  });
}
