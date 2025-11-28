import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'dart:async';
import 'dart:convert'; // Wajib untuk jsonDecode
import 'package:flutter/services.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController controller;
  bool isLoading = true;

  // Status Ujian
  bool isExamActive =
      false; // Menandakan ujian sedang berjalan (tombol keluar disembunyikan)
  bool examFinished =
      false; // Menandakan waktu habis (tombol keluar muncul lagi)

  // Default 0, Timer disembunyikan sampai server mengirim durasi
  int remainingSeconds = 0;
  Timer? countdownTimer;
  Timer? _safetyLoadingTimer;

  static const platform = MethodChannel('exambro/lockmode');

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  // --- LOGIKA MENANGKAP PESAN DARI JS ---
  void _handleJsMessage(JavaScriptMessage message) {
    String msg = message.message;
    // debugPrint("JS Message Received: $msg");

    // 1. Cek Pesan JSON (Start Exam)
    if (msg.trim().startsWith('{')) {
      try {
        Map<String, dynamic> data = jsonDecode(msg);

        if (data['type'] == 'START_EXAM') {
          // Pastikan parsing ke integer aman
          int serverDuration = int.tryParse(data['duration'].toString()) ?? 0;

          debugPrint("Durasi diterima: $serverDuration detik");

          if (mounted) {
            setState(() {
              remainingSeconds = serverDuration;
              isLoading =
                  true; // Munculkan loading saat redirect ke Google Form
              isExamActive = true; // UJIAN DIMULAI: Sembunyikan tombol keluar
              examFinished = false;
            });
            startTimer(); // Mulai hitung mundur
          }
        }
      } catch (e) {
        debugPrint("Error parsing JSON: $e");
      }
      return;
    }

    // 2. Cek Pesan Klik Tombol (Global Interceptor)
    if (msg == 'buttonClicked') {
      if (mounted) {
        setState(() => isLoading = true);

        _safetyLoadingTimer?.cancel();
        _safetyLoadingTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && isLoading) {
            setState(() => isLoading = false);
          }
        });
      }
    }
  }

  Future<void> _initializeWebView() async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController webViewController =
        WebViewController.fromPlatformCreationParams(params);

    if (webViewController.platform is AndroidWebViewController) {
      final AndroidWebViewController androidController =
          webViewController.platform as AndroidWebViewController;
      try {
        await androidController.setMediaPlaybackRequiresUserGesture(false);
      } catch (e) {
        debugPrint("Error setting media playback: $e");
      }
      AndroidWebViewController.enableDebugging(true);
    }

    webViewController
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel(
        'ClickDetector',
        onMessageReceived: _handleJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _safetyLoadingTimer?.cancel();
            if (mounted) setState(() => isLoading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => isLoading = false);

            // Inject Global Click Listener
            try {
              await controller.runJavaScript('''
                (function() {
                  if (window.isClickInterceptorActive) return;
                  window.isClickInterceptorActive = true;
                  document.addEventListener('click', function(e) {
                    var target = e.target;
                    var depth = 0;
                    while (target != null && target != document.body && depth < 5) {
                      var text = target.innerText ? target.innerText.trim().toLowerCase() : "";
                      var role = target.getAttribute ? target.getAttribute('role') : "";
                      var isNavButton = text === 'berikutnya' || text === 'next' || text === 'kirim' || text === 'submit' || text === 'kembali' || text === 'back';
                      if (role === 'button' || isNavButton) {
                        ClickDetector.postMessage('buttonClicked');
                        break; 
                      }
                      target = target.parentElement;
                      depth++;
                    }
                  }, true);
                })();
              ''');
            } catch (e) {
              debugPrint("JS Injection Error: $e");
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Izinkan navigasi ke link valid
            final url = request.url;
            if (mounted)
              setState(() => isLoading = true); // Trigger loading visual

            if (url.startsWith('http') ||
                url.startsWith('https') ||
                url.startsWith('blob:') ||
                url.contains('accounts.google.com')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    // Fix Cookies
    final WebViewCookieManager cookieManager = WebViewCookieManager();
    if (cookieManager.platform is AndroidWebViewCookieManager &&
        webViewController.platform is AndroidWebViewController) {
      try {
        await (cookieManager.platform as AndroidWebViewCookieManager)
            .setAcceptThirdPartyCookies(
              webViewController.platform as AndroidWebViewController,
              true,
            );
      } catch (e) {
        debugPrint("Gagal set cookies: $e");
      }
    }

    controller = webViewController;

    // Load URL Portal
    await controller.loadRequest(
      Uri.parse("https://masozin.github.io/portal-cbt-mtsnf/"),
    );
  }

  void startTimer() {
    countdownTimer?.cancel(); // Reset timer jika ada sebelumnya

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds <= 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            examFinished = true;
            isExamActive = false; // WAKTU HABIS: Kembalikan tombol keluar
            remainingSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            remainingSeconds--;
          });
        }
      }
    });
  }

  Future<void> _finishExam() async {
    try {
      await platform.invokeMethod("disableLockMode");
    } catch (e) {
      debugPrint("Gagal disable lock mode: $e");
    }
    if (mounted) {
      SystemNavigator.pop();
    }
  }

  Future<void> _showExitConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Konfirmasi Selesai'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text(
                  'Apakah Anda yakin ingin keluar dari ujian?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'PENTING: Pastikan Anda sudah menekan tombol KIRIM / SUBMIT pada formulir Google Form sebelum keluar. \n\nJika Anda keluar sebelum mengirim, jawaban Anda mungkin tidak terekam.',
                  style: TextStyle(color: Colors.red[800], fontSize: 13),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Ya, Saya Sudah Kirim'),
              onPressed: () {
                Navigator.of(context).pop();
                _finishExam();
              },
            ),
          ],
        );
      },
    );
  }

  String formatTime(int sec) {
    if (sec < 0) return "00:00";
    final m = sec ~/ 60;
    final s = sec % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    _safetyLoadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Hanya panggil finishExam jika ujian benar-benar selesai (Waktu Habis)
        // atau jika belum mulai sama sekali
        if (examFinished || !isExamActive) {
          // Jika ditekan tombol back fisik (kalau ada)
          if (examFinished) _finishExam();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ujian sedang berlangsung. Tidak bisa kembali.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),

              if (isLoading)
                Container(
                  color: Colors.white.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  ),
                ),

              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // --- TIMER: Muncul jika Ujian Aktif ATAU Waktu Habis ---
                    if (isExamActive || examFinished)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: remainingSeconds < 300
                              ? Colors.red[800]!.withOpacity(0.9)
                              : Colors.indigo.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
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
                                fontFamily: 'Monospace',
                              ),
                            ),
                          ],
                        ),
                      ),

                    // --- TOMBOL KELUAR: Muncul jika Ujian BELUM Aktif ATAU Waktu SUDAH Habis ---
                    // Disembunyikan saat ujian berlangsung (isExamActive == true)
                    if (!isExamActive || examFinished)
                      FloatingActionButton.extended(
                        onPressed: examFinished
                            ? _showExitConfirmation
                            : _showExitConfirmation,
                        label: const Text("Keluar"),
                        icon: const Icon(Icons.exit_to_app),
                        backgroundColor: Colors.orange,
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
