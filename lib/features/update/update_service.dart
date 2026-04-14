// ============================================================
// update_service.dart — Logika cek & unduh update dari GitHub
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../core/constants/app_constants.dart';
import 'update_info.dart';

class UpdateService {
  UpdateService._();

  // ── Ambil ABI utama perangkat ────────────────────────────────
  static Future<String> getDeviceAbi() async {
    if (!Platform.isAndroid) return '';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      if (abis.isNotEmpty) return abis.first;
    } catch (e) {
      debugPrint('[UpdateService] Gagal deteksi ABI: $e');
    }
    return '';
  }

  // ── Cek update dari GitHub Releases ─────────────────────────
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(
            Uri.parse(AppConstants.githubApiUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[UpdateService] GitHub API error: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = (json['tag_name'] as String)
          .replaceAll('v', '')
          .trim();
      final releaseNotes = (json['body'] as String? ?? '').trim();
      final assets = json['assets'] as List<dynamic>? ?? [];

      final abi = await getDeviceAbi();
      debugPrint('[UpdateService] ABI perangkat: $abi');

      final apkAsset = _findBestApkAsset(assets, abi);
      if (apkAsset == null) {
        debugPrint('[UpdateService] Tidak ada APK asset yang sesuai.');
        return null;
      }

      final info = UpdateInfo(
        latestVersion: latestVersion,
        downloadUrl: apkAsset['browser_download_url'] as String,
        releaseNotes: releaseNotes,
        hasUpdate: _isNewerVersion(latestVersion, currentVersion),
        apkName: apkAsset['name'] as String,
      );

      debugPrint('[UpdateService] $info');
      return info;
    } catch (e) {
      debugPrint('[UpdateService] Gagal cek update: $e');
      return null;
    }
  }

  // ── Pilih APK terbaik: ABI match → universal → fallback ─────
  static Map<String, dynamic>? _findBestApkAsset(
    List<dynamic> assets,
    String abi,
  ) {
    final apks = assets
        .whereType<Map<String, dynamic>>()
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.apk'))
        .toList();

    if (apks.isEmpty) return null;

    // 1. Cocokkan ABI persis
    if (abi.isNotEmpty) {
      final exact = apks.where(
        (a) => (a['name'] as String).toLowerCase().contains(abi.toLowerCase()),
      );
      if (exact.isNotEmpty) return exact.first;
    }

    // 2. Universal (tidak mengandung keyword ABI spesifik)
    final universal = apks.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return !AppConstants.abiKeywords.any((k) => name.contains(k));
    });
    if (universal.isNotEmpty) return universal.first;

    // 3. Fallback: APK pertama
    return apks.first;
  }

  // ── Bandingkan versi semantik ────────────────────────────────
  static bool _isNewerVersion(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
    } catch (_) {}
    return false;
  }
}
