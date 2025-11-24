import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'webview_page.dart';

const platform = MethodChannel('exambro/lockmode');
const dndChannel = MethodChannel('exam.channel');

void main() {
  runApp(const ExambroApp());
}

class ExambroApp extends StatelessWidget {
  const ExambroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Exambro',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const ExamPage(),
    );
  }
}

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  bool _isLockModeActive = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockModeStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLockModeStatus();
    }
  }

  Future<void> _checkLockModeStatus() async {
    try {
      final isActive = await platform.invokeMethod("isLockTaskActive");
      debugPrint("Single Check Lock Status: $isActive"); // DEBUG
      if (mounted) {
        setState(() {
          _isLockModeActive = isActive == true;
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Error checking lock status: ${e.message}");
    }
  }

  Future<void> _handleStartExam(BuildContext context) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // 1. CEK DND TERLEBIH DAHULU
      final bool dndGranted = await dndChannel.invokeMethod(
        "checkAndEnableDND",
      );

      if (!dndGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Harap izinkan akses 'Jangan Ganggu' lalu coba lagi.",
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      // 2. JIKA DND AMAN, LANJUT ENABLE LOCK MODE
      debugPrint("Requesting Lock Mode...");
      await platform.invokeMethod("enableLockMode");

      // 3. POLLING (MENUNGGU USER KLIK 'MENGERTI')
      bool isActive = false;
      int maxAttempts = 30;
      int attempts = 0;

      while (!isActive && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 500));

        final status = await platform.invokeMethod("isLockTaskActive");
        debugPrint(
          "Polling Attempt #$attempts: Status Native = $status",
        ); // DEBUG LOG

        isActive = status == true;
        attempts++;

        if (mounted) {
          setState(() {
            _isLockModeActive = isActive;
          });
        }

        if (isActive) break;
      }

      // 4. NAVIGASI
      if (isActive && mounted) {
        debugPrint("Lock Mode CONFIRMED. Navigating to Webview.");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WebviewPage()),
        );
      } else if (mounted) {
        debugPrint("Lock Mode FAILED/TIMEOUT after $attempts attempts.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Gagal masuk mode ujian. Pastikan Anda klik 'MENGERTI'.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: ${e.message}")));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> exitApp() async {
    await platform.invokeMethod("exitExam");
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Exambro - Halaman Utama"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isLockModeActive ? Icons.lock : Icons.lock_open,
                size: 80,
                color: _isLockModeActive ? Colors.green : Colors.indigo,
              ),
              const SizedBox(height: 20),
              Text(
                _isLockModeActive ? "Mode Aman Aktif" : "Mode Aman Nonaktif",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _handleStartExam(context),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isProcessing ? "Memproses..." : "Mulai Ujian"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isLockModeActive ? null : exitApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text("Keluar Aplikasi"),
        ),
      ),
    );
  }
}
