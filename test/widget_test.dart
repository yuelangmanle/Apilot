import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/app.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const ApiManagerApp());
    expect(find.text('API管理器'), findsOneWidget);
  });
}
