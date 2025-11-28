import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'webview_page.dart'; // Pastikan file ini ada di project Anda

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
      // Mengaktifkan Material 3 untuk tampilan yang lebih modern
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: Colors.grey[50],
      ),
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
      debugPrint("Single Check Lock Status: $isActive");
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
      // 1. CEK DND
      final bool dndGranted = await dndChannel.invokeMethod(
        "checkAndEnableDND",
      );

      if (!dndGranted) {
        if (mounted) {
          _showSnackBar(
            context,
            "Harap izinkan akses 'Jangan Ganggu' lalu coba lagi.",
            isError: true,
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      // 2. ENABLE LOCK MODE
      debugPrint("Requesting Lock Mode...");
      await platform.invokeMethod("enableLockMode");

      // 3. POLLING
      bool isActive = false;
      int maxAttempts = 30;
      int attempts = 0;

      while (!isActive && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 500));
        final status = await platform.invokeMethod("isLockTaskActive");
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WebviewPage()),
        );
      } else if (mounted) {
        _showSnackBar(
          context,
          "Gagal masuk mode ujian. Pastikan Anda klik 'MENGERTI'.",
          isError: true,
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        _showSnackBar(context, "Error: ${e.message}", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.indigo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> exitApp() async {
    // Tambahan konfirmasi dialog agar tidak terpencet tidak sengaja
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Keluar Aplikasi?"),
            content: const Text("Apakah Anda yakin ingin menutup aplikasi?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Batal"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Ya, Keluar",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await platform.invokeMethod("exitExam");
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.indigo, Color(0xFFE8EAF6)],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // --- HEADER AREA ---
              const SizedBox(height: 40),
              const Text(
                "CBT EXAM BROWSER",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "MTs Nurul Falah",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // --- MAIN CARD CONTENT ---
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // LOGO SECTION
                      Container(
                        height: 150,
                        width: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.indigo.withOpacity(0.1),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Image.asset(
                              'assets/logo_sekolah.png', // Ganti dengan nama file logo Anda
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                // Tampilan jika logo tidak ditemukan
                                return const Icon(
                                  Icons.school_rounded,
                                  size: 60,
                                  color: Colors.indigo,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // STATUS INDICATOR
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _isLockModeActive
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: _isLockModeActive
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLockModeActive
                                  ? Icons.lock_outline
                                  : Icons.lock_open_rounded,
                              color: _isLockModeActive
                                  ? Colors.green
                                  : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isLockModeActive
                                  ? "Sistem Terkunci & Aman"
                                  : "Sistem Belum Terkunci",
                              style: TextStyle(
                                color: _isLockModeActive
                                    ? Colors.green[700]
                                    : Colors.orange[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // BUTTON START
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _handleStartExam(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            elevation: 5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "MULAI UJIAN",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Icon(Icons.arrow_forward_rounded),
                                  ],
                                ),
                        ),
                      ),
                      const Spacer(),

                      // BUTTON EXIT
                      TextButton.icon(
                        onPressed: _isLockModeActive ? null : exitApp,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text("Keluar Aplikasi"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          disabledForegroundColor: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "v1.0.0 Exambro",
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
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
