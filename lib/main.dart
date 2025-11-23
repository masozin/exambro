  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'webview_page.dart';

  const platform = MethodChannel('exambro/lockmode');

  void main() {
    runApp(const ExambroApp());
  }

  class ExambroApp extends StatelessWidget {
    const ExambroApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const ExamPage(),
      );
    }
  }

  class ExamPage extends StatelessWidget {
    const ExamPage({super.key});

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const WebviewPage()),
              );
            },
            child: const Text("Mulai Ujian"),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: ElevatedButton(
            onPressed: () {
              SystemNavigator.pop();
            },
            child: const Text("Keluar"),
          ),
        ),
      );
    }
  }
