// ============================================================
// app_constants.dart — Semua konstanta global aplikasi
// ============================================================

class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Exambro';
  static const String schoolName = 'MTs Nurul Falah';
  static const String appVersion = '1.0.1';

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

  // Timer
  static const int lastMinutesWarning = 600;
  static const int midWarningSeconds = 1800;
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
