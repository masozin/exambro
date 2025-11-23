import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController controller;
  bool isLoading = true;
  bool examFinished = false;

  // Timer (sementara 1 menit untuk test)
  int remainingSeconds = 1 * 60;
  Timer? countdownTimer;

  static const platform = MethodChannel('exambro/lockmode');

  @override
  void initState() {
    super.initState();

    // LOCK TASK MODE
    platform.invokeMethod("enableLockMode");

    // WEBVIEW
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() => isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse("https://masozin.github.io/asesmen-mtsnf/"));

    startTimer();
  }

  void startTimer() {
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (remainingSeconds <= 0) {
        timer.cancel();
        setState(() {
          examFinished = true;
        });
      } else {
        setState(() {
          remainingSeconds--;
        });
      }
    });
  }

  Future<void> exitApp() async {
    await platform.invokeMethod("disableLockMode");
    SystemNavigator.pop();
  }

  String formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (!examFinished) {
      // jangan keluar selama ujian berlangsung
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ujian sedang berlangsung.')),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,

      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // WEBVIEW
              WebViewWidget(controller: controller),

              // LOADING
              if (isLoading) const Center(child: CircularProgressIndicator()),

              // PANEL TIMER + EXIT (pojok kanan bawah)
              Positioned(
                bottom: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // TIMER
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "⏳ ${formatTime(remainingSeconds)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // BUTTON EXIT (tampil saat ujian selesai)
                    if (examFinished)
                      ElevatedButton(
                        onPressed: exitApp,
                        child: const Text("Keluar"),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
