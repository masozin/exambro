// ============================================================
// exam_service.dart — Komunikasi dengan platform native (lock, DND)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';

class ExamService {
  ExamService._();

  static const _lockChannel = MethodChannel(AppConstants.lockModeChannel);
  static const _dndChannel = MethodChannel(AppConstants.dndChannel);

  // ── Lock Mode ────────────────────────────────────────────────

  static Future<bool> enableLockMode() async {
    try {
      await _lockChannel.invokeMethod('enableLockMode');
      return true;
    } on PlatformException catch (e) {
      debugPrint('[ExamService] enableLockMode error: ${e.message}');
      return false;
    }
  }

  static Future<bool> disableLockMode() async {
    try {
      await _lockChannel.invokeMethod('disableLockMode');
      return true;
    } on PlatformException catch (e) {
      debugPrint('[ExamService] disableLockMode error: ${e.message}');
      return false;
    }
  }

  static Future<bool> isLockModeActive() async {
    try {
      final result = await _lockChannel.invokeMethod<bool>('isLockTaskActive');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ExamService] isLockModeActive error: ${e.message}');
      return false;
    }
  }

  static Future<void> exitExam() async {
    try {
      await _lockChannel.invokeMethod('exitExam');
    } on PlatformException catch (e) {
      debugPrint('[ExamService] exitExam error: ${e.message}');
    }
  }

  // ── DND (Do Not Disturb) ─────────────────────────────────────

  /// Hanya cek status DND tanpa membuka settings atau mengubah filter.
  /// Mengembalikan true jika izin policy access sudah diberikan.
  static Future<bool> isDndGranted() async {
    try {
      final result = await _dndChannel.invokeMethod<bool>('checkAndEnableDND', {
        'openSettings': false,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ExamService] isDndGranted error: ${e.message}');
      return false;
    }
  }

  /// [openSettings] = true hanya saat pertama kali meminta izin.
  /// Gunakan false saat polling status.
  static Future<bool> checkAndEnableDnd({bool openSettings = true}) async {
    try {
      final result = await _dndChannel.invokeMethod<bool>('checkAndEnableDND', {
        'openSettings': openSettings,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ExamService] checkAndEnableDnd error: ${e.message}');
      return false;
    }
  }

  // ── Polling DND hingga granted ───────────────────────────────
  /// Buka settings sekali, lalu poll setiap 1 detik hingga [maxAttempts].
  /// Kembalikan true jika berhasil, false jika timeout.
  static Future<bool> waitForDndGrant({
    int maxAttempts = AppConstants.dndMaxAttempts,
  }) async {
    // Buka settings
    await checkAndEnableDnd(openSettings: true);

    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final granted = await checkAndEnableDnd(openSettings: false);
      if (granted) return true;
    }
    return false;
  }

  // ── Polling Lock Mode hingga aktif ───────────────────────────
  static Future<bool> waitForLockMode({
    int maxAttempts = AppConstants.lockMaxAttempts,
  }) async {
    await enableLockMode();

    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final active = await isLockModeActive();
      if (active) return true;
    }
    return false;
  }
}
