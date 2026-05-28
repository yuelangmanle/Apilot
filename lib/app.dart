import 'package:flutter/material.dart';
import 'shared/theme/app_theme.dart';

class ApiManagerApp extends StatelessWidget {
  const ApiManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API管理器',
      theme: AppTheme.lightTheme,
      home: const Scaffold(
        body: Center(
          child: Text('API管理器'),
        ),
      ),
    );
  }
}
