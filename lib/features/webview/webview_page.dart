// ============================================================
// webview_page.dart — Halaman ujian: WebView + Timer + Kamera Overlay
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../camera/camera_service.dart';
import '../camera/camera_overlay.dart';
import '../exam/exam_service.dart';
import '../../core/constants/app_constants.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({super.key});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  // ── WebView ──────────────────────────────────────────────────
  late final WebViewController _webController;
  bool _isLoading = true;

  // ── Exam State ───────────────────────────────────────────────
  bool _isExamActive = false;
  bool _examFinished = false;
  bool _isSubmitted = false;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  Timer? _safetyLoadingTimer;

  // ── Camera ───────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _isFaceDetected = true; // Default true agar tidak langsung merah

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initWebView();
    _initCamera();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _safetyLoadingTimer?.cancel();
    CameraService.dispose();
    super.dispose();
  }

  // ── Camera Init ──────────────────────────────────────────────

  Future<void> _initCamera() async {
    final controller = await CameraService.initialize();
    if (controller != null && mounted) {
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
      // Mulai deteksi wajah
      CameraService.startFaceDetection((detected) {
        if (mounted) setState(() => _isFaceDetected = detected);
      });
    }
  }

  // ── WebView Init ─────────────────────────────────────────────

  Future<void> _initWebView() async {
    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    if (controller.platform is AndroidWebViewController) {
      final androidCtrl = controller.platform as AndroidWebViewController;
      await androidCtrl.setMediaPlaybackRequiresUserGesture(false);
      AndroidWebViewController.enableDebugging(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..addJavaScriptChannel('ClickDetector', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _safetyLoadingTimer?.cancel();
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _isLoading = false);
            await _injectClickInterceptor();
          },
          onNavigationRequest: (req) {
            if (mounted) setState(() => _isLoading = true);
            final url = req.url;
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

    // Accept third-party cookies (diperlukan Google Form)
    final cookieManager = WebViewCookieManager();
    if (cookieManager.platform is AndroidWebViewCookieManager &&
        controller.platform is AndroidWebViewController) {
      await (cookieManager.platform as AndroidWebViewCookieManager)
          .setAcceptThirdPartyCookies(
            controller.platform as AndroidWebViewController,
            true,
          );
    }

    _webController = controller;
    await _webController.loadRequest(Uri.parse(AppConstants.portalUrl));
  }

  // ── JS Injection ─────────────────────────────────────────────

  Future<void> _injectClickInterceptor() async {
    try {
      await _webController.runJavaScript('''
        (function() {
          if (window.__exambroInjected) return;
          window.__exambroInjected = true;

          // --- Deteksi halaman konfirmasi submit Google Form ---
          // Cek saat halaman selesai load apakah sudah ada teks konfirmasi
          function checkIfSubmitted() {
            var bodyText = document.body ? document.body.innerText : '';
            var confirmedPhrases = [
              'jawaban telah terkirim',
              'your response has been recorded',
              'respons anda telah dicatat',
              'tanggapan anda telah dicatat',
              'response recorded',
            ];
            for (var i = 0; i < confirmedPhrases.length; i++) {
              if (bodyText.toLowerCase().includes(confirmedPhrases[i])) {
                ClickDetector.postMessage('FORM_SUBMITTED');
                return true;
              }
            }
            return false;
          }

          // Cek langsung saat inject (jika sudah di halaman konfirmasi)
          checkIfSubmitted();

          // Observer: pantau perubahan DOM (redirect setelah submit)
          var observer = new MutationObserver(function() {
            if (checkIfSubmitted()) {
              observer.disconnect(); // Hentikan observer setelah terdeteksi
            }
          });
          observer.observe(document.body || document.documentElement, {
            childList: true,
            subtree: true,
            characterData: true,
          });

          // --- Global click interceptor untuk loading indicator ---
          document.addEventListener('click', function(e) {
            var target = e.target;
            var depth = 0;
            while (target && target !== document.body && depth < 5) {
              var text = (target.innerText || '').trim().toLowerCase();
              var role = target.getAttribute ? target.getAttribute('role') : '';
              var isNav = text === 'berikutnya' || text === 'next' ||
                          text === 'kirim'      || text === 'submit' ||
                          text === 'kembali'    || text === 'back';
              if (role === 'button' || isNav) {
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
      debugPrint('[WebviewPage] JS injection error: $e');
    }
  }

  Future<void> _updateSubmitButtonState(bool allowSubmit) async {
    final js =
        '''
      (function() {
        var buttons = document.querySelectorAll('[role="button"]');
        var allow = $allowSubmit;
        for (var i = 0; i < buttons.length; i++) {
          var btn = buttons[i];
          var text = btn.innerText.toLowerCase().trim();
          var isSubmit = text === 'kirim' || text === 'submit' || text.includes('tunggu..');
          var isBack   = text === 'kembali' || text === 'back';
          if (isSubmit && !isBack) {
            if (allow) {
              if (btn.style.pointerEvents === 'none') {
                btn.style.pointerEvents = 'auto';
                btn.style.opacity = '1';
                btn.innerText = 'Kirim';
              }
              btn.onclick = function() { ClickDetector.postMessage('FORM_SUBMITTED'); };
            } else {
              if (btn.innerText !== 'Tunggu..') {
                btn.style.pointerEvents = 'none';
                btn.style.opacity = '0.5';
                btn.innerText = 'Tunggu..';
              }
            }
          }
        }
      })();
    ''';
    try {
      await _webController.runJavaScript(js);
    } catch (_) {}
  }

  // ── JS Message Handler ───────────────────────────────────────

  void _onJsMessage(JavaScriptMessage message) {
    final msg = message.message;

    if (msg == 'FORM_SUBMITTED') {
      debugPrint('[WebviewPage] Form submitted detected!');
      if (mounted) {
        setState(() {
          _isSubmitted = true;
          // Ujian dianggap selesai dari sisi siswa — tombol keluar boleh muncul
          _isExamActive = false;
        });
      }
      return;
    }

    if (msg.trim().startsWith('{')) {
      try {
        final data = jsonDecode(msg) as Map<String, dynamic>;
        if (data['type'] == 'START_EXAM') {
          final duration = int.tryParse(data['duration'].toString()) ?? 0;
          if (mounted) {
            setState(() {
              _remainingSeconds = duration;
              _isLoading = true;
              _isExamActive = true;
              _examFinished = false;
            });
            _startTimer();
          }
        }
      } catch (e) {
        debugPrint('[WebviewPage] JSON parse error: $e');
      }
      return;
    }

    if (msg == 'buttonClicked' && mounted) {
      setState(() => _isLoading = true);
      _safetyLoadingTimer?.cancel();
      _safetyLoadingTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isLoading) setState(() => _isLoading = false);
      });
    }
  }

  // ── Timer ────────────────────────────────────────────────────

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _examFinished = true;
            _isExamActive = false;
            _remainingSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() => _remainingSeconds--);
          final isLast5Min =
              _remainingSeconds <= AppConstants.lastMinutesWarning;
          _updateSubmitButtonState(isLast5Min);
        }
      }
    });
  }

  String _formatTime(int sec) {
    if (sec <= 0) return '00:00';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Exit Handlers ────────────────────────────────────────────

  Future<void> _finishExam() async {
    await ExamService.disableLockMode();
    if (mounted) SystemNavigator.pop();
  }

  Future<void> _showExitConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Selesai'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Apakah Anda yakin ingin keluar dari ujian?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'PENTING: Pastikan Anda sudah menekan tombol KIRIM / SUBMIT '
                'sebelum keluar. Jawaban yang belum dikirim tidak akan terekam.',
                style: TextStyle(color: Colors.red[800], fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              _finishExam();
            },
            child: const Text('Ya, Saya Sudah Kirim'),
          ),
        ],
      ),
    );
  }

  Future<void> _exitApp() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar Aplikasi?'),
        content: const Text('Apakah Anda yakin ingin menutup aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Ya, Keluar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) await _finishExam();
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── Warna bar 3 tingkat ──────────────────────────────────
    // Biru   : > 30 menit / ujian belum aktif
    // Kuning : ≤ 30 menit (1800 detik)
    // Merah  : ≤ lastMinutesWarning (5 menit default)
    Color barColor;
    if (!_isExamActive && !_examFinished) {
      barColor = Colors.indigo.withOpacity(0.85);
    } else if (_remainingSeconds <= AppConstants.lastMinutesWarning) {
      barColor = Colors.red[800]!.withOpacity(0.90);
    } else if (_remainingSeconds <= AppConstants.midWarningSeconds) {
      barColor = Colors.orange[700]!.withOpacity(0.90);
    } else {
      barColor = Colors.indigo.withOpacity(0.85);
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_examFinished) {
          _finishExam();
        } else if (!_isExamActive) {
          _exitApp();
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
              // ── WebView fullscreen ──────────────────────────
              Positioned.fill(child: WebViewWidget(controller: _webController)),

              // ── Loading Overlay ─────────────────────────────
              if (_isLoading)
                Container(
                  color: Colors.white.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.indigo),
                  ),
                ),

              // ── Camera Overlay (pojok kiri atas) ───────────
              if (_cameraReady && _cameraController != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: CameraOverlay(
                    controller: _cameraController!,
                    isFaceDetected: _isFaceDetected,
                  ),
                ),

              // ── Bottom Navigation Bar (Pill) ────────────────
              Positioned(
                bottom: 10,
                left: 15,
                right: 15,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Navigasi WebView
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NavIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Kembali',
                            onPressed: () async {
                              if (await _webController.canGoBack()) {
                                await _webController.goBack();
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Tidak ada riwayat kembali',
                                      ),
                                      duration: Duration(milliseconds: 500),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          _NavIconButton(
                            icon: Icons.refresh,
                            tooltip: 'Muat Ulang',
                            onPressed: () => _webController.reload(),
                          ),
                          _NavIconButton(
                            icon: Icons.arrow_forward,
                            tooltip: 'Maju',
                            onPressed: () async {
                              if (await _webController.canGoForward()) {
                                await _webController.goForward();
                              }
                            },
                          ),
                        ],
                      ),

                      // Timer (muncul saat ujian aktif/selesai)
                      if (_isExamActive || _examFinished)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatTime(_remainingSeconds),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'Monospace',
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox(width: 40),

                      // Tombol keluar:
                      // Muncul jika: ujian belum mulai, waktu habis, atau sudah submit
                      if (!_isExamActive || _examFinished || _isSubmitted)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            onPressed: (_examFinished || _isSubmitted)
                                ? _showExitConfirmation
                                : _exitApp,
                            icon: const Icon(
                              Icons.power_settings_new,
                              color: Colors.white,
                            ),
                            tooltip: 'Keluar',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.2),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 56),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable icon button untuk navigasi ─────────────────────
class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
