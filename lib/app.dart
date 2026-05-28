import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'shared/theme/app_theme.dart';
import 'core/services/database_service.dart';
import 'features/api_management/providers/api_provider.dart';
import 'features/api_management/screens/api_list_screen.dart';

class ApiManagerApp extends StatelessWidget {
  const ApiManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ApiProvider(DatabaseService()),
        ),
      ],
      child: MaterialApp(
        title: 'API管理器',
        theme: AppTheme.lightTheme,
        home: const ApiListScreen(),
      ),
    );
  }
}
