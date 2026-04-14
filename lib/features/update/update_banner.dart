// ============================================================
// update_banner.dart — Banner & progress unduh update
// ============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'update_info.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _isDownloading = false;
  double _progress = 0;

  Future<void> _downloadAndInstall() async {
    // Minta izin install APK dari sumber tidak dikenal
    final permission = await Permission.requestInstallPackages.request();
    if (!permission.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Izin instalasi diperlukan. Aktifkan di Pengaturan.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0;
    });

    try {
      final dir = await getTemporaryDirectory();
      final apkPath = p.join(
        dir.path,
        'exambro_update_${widget.info.latestVersion}.apk',
      );
      final file = File(apkPath);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.info.downloadUrl));
      final response = await client.send(request);
      final total = response.contentLength ?? 0;
      int received = 0;

      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      });
      await sink.close();
      client.close();

      await OpenFile.open(apkPath);
    } catch (e) {
      debugPrint('[UpdateBanner] Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengunduh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update tersedia: v${widget.info.latestVersion}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (widget.info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.info.releaseNotes,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          if (_isDownloading) ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey[200],
              color: Colors.amber,
            ),
            const SizedBox(height: 4),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _downloadAndInstall,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Unduh & Pasang Update'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
