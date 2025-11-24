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
  int remainingSeconds = 5 * 60; // Contoh 5 menit
  Timer? countdownTimer;

  static const platform = MethodChannel('exambro/lockmode');

  @override
  void initState() {
    super.initState();

    // Inisialisasi Controller
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 1. TAMBAHAN PENTING: Set User Agent agar Google Form tidak redirect ke aplikasi native
      ..setUserAgent(
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
          onWebResourceError: (error) {
            // Filter error agar tidak spam di UI jika hanya error redirect
            if (error.description.contains("net::ERR_FILE_NOT_FOUND")) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error memuat: ${error.description}")),
            );
          },
          // 2. TAMBAHAN PENTING: Mencegah navigasi ke intent:// atau market://
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            // Hanya izinkan HTTP dan HTTPS
            if (url.startsWith('http://') || url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }

            // Blokir intent://, file://, mailto:, whatsapp:, dll agar tidak error FILE_NOT_FOUND
            debugPrint("Memblokir navigasi eksternal: $url");
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse("https://masozin.github.io/asesmen-mtsnf/"));

    // Bersihkan cache agar sesi login fresh (Opsional, tapi disarankan untuk ujian)
    controller.clearCache();
    controller.clearLocalStorage();

    startTimer();
  }

  void startTimer() {
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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

  // Fungsi untuk keluar ujian dengan aman
  Future<void> _finishExam() async {
    // 1. Matikan Lock Mode
    try {
      await platform.invokeMethod("disableLockMode");
    } catch (e) {
      debugPrint("Gagal disable lock mode: $e");
    }

    // 2. Navigasi kembali ke halaman utama
    if (mounted) {
      Navigator.pop(context);
    }
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Mencegah tombol back sistem
      onPopInvoked: (didPop) {
        if (didPop) return;

        if (examFinished) {
          _finishExam();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ujian sedang berlangsung. Tidak bisa kembali.'),
            ),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (isLoading) const Center(child: CircularProgressIndicator()),

              // Floating Timer & Exit Control
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatTime(remainingSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (examFinished)
                      FloatingActionButton.extended(
                        onPressed: _finishExam,
                        label: const Text("Selesai & Keluar"),
                        icon: const Icon(Icons.check_circle),
                        backgroundColor: Colors.green,
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
