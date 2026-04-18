// ============================================================
// app_constants.dart — Semua konstanta global aplikasi
// ============================================================

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'ExamNF';
  static const String schoolName = 'MTs Nurul Falah';
  static const String appVersion = '1.0.3';

  // GitHub Update
  static const String githubOwner = 'masozin';
  static const String githubRepo = 'exambro';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  // Platform Channels
  static const String lockModeChannel = 'exambro/lockmode';
  static const String dndChannel = 'exam.channel';

  // Portal Ujian
  static const String portalUrl = 'https://masozin.github.io/portal-cbt-mtsnf/';

  // ── Token Autentikasi WebView ────────────────────────────────
  // Token ini di-inject ke setiap halaman oleh Flutter via JavaScript.
  // GitHub Pages memverifikasinya — jika tidak cocok, halaman diblokir.
  //
  // ⚠️  WAJIB DIGANTI sebelum produksi!
  //     Gunakan string acak panjang, contoh gabungkan 2 UUID:
  //     https://www.uuidgenerator.net/
  //
  // ⚠️  Token yang sama HARUS diisi di index.html GitHub Pages
  //     pada variabel: const VALID_TOKEN = '...';
  static const String webviewToken = appVersion;

  // Timer
  static const int lastMinutesWarning = 600; //detik
  static const int midWarningSeconds = 1800; //detik
  static const int dndMaxAttempts = 30;
  static const int lockMaxAttempts = 30;

  // ABI Keywords
  static const List<String> abiKeywords = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  // Camera Overlay Size
  static const double cameraWidth = 80.0;
  static const double cameraHeight = 100.0;
}
