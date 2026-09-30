import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('App Integration Test', () {
    testWidgets('should display API list screen', (tester) async {
      await tester.pumpWidget(const ApiManagerApp());
      await tester.pumpAndSettle();

      expect(find.text('Apilot'), findsOneWidget);
    });
  });
}
