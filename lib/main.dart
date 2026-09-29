import 'package:flutter/material.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiManagerApp.bootstrap();
  runApp(const ApiManagerApp());
}
