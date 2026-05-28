import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('App Integration Test', () {
    testWidgets('should display API list screen', (tester) async {
      await tester.pumpWidget(const ApiManagerApp());
      await tester.pump();

      expect(find.text('API管理器'), findsOneWidget);
    });
  });
}
