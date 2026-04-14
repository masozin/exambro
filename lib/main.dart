// ============================================================
// main.dart — Entry point aplikasi Exambro
// ============================================================

import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'features/exam/exam_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExambroApp());
}

class ExambroApp extends StatelessWidget {
  const ExambroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const ExamPage(),
    );
  }
}
