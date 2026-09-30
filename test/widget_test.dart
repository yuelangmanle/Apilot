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

  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const ApiManagerApp());
    // 应用锁控制器异步初始化（LockGate 短暂显示加载页），等待其完成。
    await tester.pumpAndSettle();
    expect(find.text('Apilot'), findsOneWidget);
  });
}
