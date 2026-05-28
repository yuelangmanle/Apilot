import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:api_manager/app.dart';

void main() {
  // Initialize sqflite for testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('App Integration Test', () {
    testWidgets('should display API list screen', (tester) async {
      await tester.pumpWidget(const ApiManagerApp());

      expect(find.text('API管理器'), findsOneWidget);
      expect(find.text('还没有API配置'), findsOneWidget);
    });

    testWidgets('should show FAB button', (tester) async {
      await tester.pumpWidget(const ApiManagerApp());

      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
