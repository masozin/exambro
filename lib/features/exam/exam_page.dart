// ============================================================
// exam_page.dart — Halaman utama dengan checklist izin
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../update/update_service.dart';
import '../update/update_info.dart';
import '../update/update_banner.dart';
import '../exam/exam_service.dart';
import '../webview/webview_page.dart';
import '../../core/constants/app_constants.dart';

// ── Model satu item izin ─────────────────────────────────────
class _PermItem {
  final String label;
  final String description;
  final IconData icon;
  final bool required; // wajib = blokir tombol mulai jika belum granted
  bool granted;
  bool loading;

  _PermItem({
    required this.label,
    required this.description,
    required this.icon,
    required this.required,
    this.granted = false,
    this.loading = false,
  });
}

// ============================================================

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  bool _isLockModeActive = false;
  bool _isProcessing = false;
  UpdateInfo? _updateInfo;

  late final List<_PermItem> _perms;

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _perms = [
      _PermItem(
        label: 'Jangan Ganggu (DND)',
        description: 'Mencegah notifikasi masuk selama ujian berlangsung.',
        icon: Icons.do_not_disturb_on_rounded,
        required: true,
      ),
      _PermItem(
        label: 'Kamera',
        description: 'Memantau kehadiran siswa selama ujian.',
        icon: Icons.camera_alt_rounded,
        required: true,
      ),
      _PermItem(
        label: 'Penyematan Layar',
        description: 'Mengunci layar agar tidak bisa keluar saat ujian.',
        icon: Icons.lock_rounded,
        required: false, // dikonfirmasi native saat mulai, bukan permission_handler
        granted: false,
      ),
      _PermItem(
        label: 'Instal Aplikasi',
        description: 'Mengizinkan pembaruan otomatis dari server sekolah.',
        icon: Icons.system_update_rounded,
        required: false,
      ),
    ];

    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
    _checkLockStatus();
    _checkUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
      _checkLockStatus();
    }
  }

  // ── Check semua izin ─────────────────────────────────────────

  Future<void> _checkAllPermissions() async {
    await Future.wait([
      _checkDnd(),
      _checkCamera(),
      _checkInstall(),
    ]);
    // Index 2 = Penyematan Layar: tidak bisa dicek via permission_handler,
    // dibiarkan granted=false dan ditampilkan sebagai "Saat ujian"
  }

  Future<void> _checkDnd() async {
    final granted = await ExamService.isDndGranted();
    _setPermState(0, granted);
  }

  Future<void> _checkCamera() async {
    final status = await Permission.camera.status;
    _setPermState(1, status.isGranted);
  }

  Future<void> _checkInstall() async {
    final status = await Permission.requestInstallPackages.status;
    _setPermState(3, status.isGranted);
  }

  void _setPermState(int index, bool granted) {
    if (mounted) {
      setState(() {
        _perms[index].granted = granted;
        _perms[index].loading = false;
      });
    }
  }

  // ── Request izin individual ──────────────────────────────────

  Future<void> _requestPermission(int index) async {
    setState(() => _perms[index].loading = true);

    switch (index) {
      case 0: // DND — buka Settings lalu polling 10 detik
        await ExamService.checkAndEnableDnd(openSettings: true);
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(seconds: 1));
          final ok = await ExamService.isDndGranted();
          if (ok) { _setPermState(0, true); return; }
        }
        _setPermState(0, false);

      case 1: // Kamera
        final result = await Permission.camera.request();
        if (!result.isGranted && mounted) openAppSettings();
        _setPermState(1, result.isGranted);

      case 3: // Install APK
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted && mounted) openAppSettings();
        _setPermState(3, result.isGranted);
    }
  }

  // ── Semua izin WAJIB sudah granted? ─────────────────────────

  bool get _canStart =>
      _perms.where((p) => p.required).every((p) => p.granted);

  // ── Aksi ─────────────────────────────────────────────────────

  Future<void> _checkLockStatus() async {
    final active = await ExamService.isLockModeActive();
    if (mounted) setState(() => _isLockModeActive = active);
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (mounted && info != null && info.hasUpdate) {
      setState(() => _updateInfo = info);
    }
  }

  Future<void> _handleStartExam() async {
    if (_isProcessing || !_canStart) return;
    setState(() => _isProcessing = true);

    try {
      // DND sudah granted — langsung aktifkan filter
      await ExamService.checkAndEnableDnd(openSettings: false);

      // Lock Mode
      final lockActive = await ExamService.waitForLockMode();
      if (mounted) setState(() => _isLockModeActive = lockActive);

      if (lockActive && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WebviewPage()),
        );
      } else if (mounted) {
        _showSnackBar(
          'Gagal masuk mode ujian. Klik "MENGERTI/GOT IT" pada popup penyematan layar.',
          isError: true,
        );
      }
    } on PlatformException catch (e) {
      if (mounted) _showSnackBar('Error Sistem: ${e.message}', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleExit() async {
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
            child: const Text('Ya, Keluar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ExamService.exitExam();
      SystemNavigator.pop();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.indigo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────

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
              // ── Header ─────────────────────────────────────
              const SizedBox(height: 28),
              const Text(
                'CBT EXAM BROWSER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                AppConstants.schoolName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // ── Card Utama ──────────────────────────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      children: [
                        // Logo
                        _SchoolLogo(),
                        const SizedBox(height: 16),

                        // Banner update
                        if (_updateInfo != null && _updateInfo!.hasUpdate) ...[
                          UpdateBanner(info: _updateInfo!),
                          const SizedBox(height: 12),
                        ],

                        // ── Checklist Izin ──────────────────
                        _PermissionCard(
                          perms: _perms,
                          onRequest: _requestPermission,
                        ),
                        const SizedBox(height: 14),

                        // Status lock
                        _LockStatusIndicator(isActive: _isLockModeActive),
                        const SizedBox(height: 18),

                        // Tombol mulai
                        _StartButton(
                          isProcessing: _isProcessing,
                          canStart: _canStart,
                          onPressed: _handleStartExam,
                          onBlocked: () => _showSnackBar(
                            'Aktifkan semua izin wajib (DND & Kamera) terlebih dahulu.',
                            isError: true,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Tombol keluar
                        TextButton.icon(
                          onPressed: _handleExit,
                          icon: const Icon(Icons.logout_rounded, size: 17),
                          label: const Text('Keluar Aplikasi'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'v${AppConstants.appVersion} ${AppConstants.appName}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
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

// ============================================================
// Widget: Kartu Checklist Izin
// ============================================================

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.perms, required this.onRequest});

  final List<_PermItem> perms;
  final Future<void> Function(int index) onRequest;

  @override
  Widget build(BuildContext context) {
    final requiredGranted = perms.where((p) => p.required && p.granted).length;
    final totalRequired = perms.where((p) => p.required).length;
    final allOk = requiredGranted == totalRequired;
    final grantedCount = perms.where((p) => p.granted).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allOk ? Colors.green.shade300 : Colors.orange.shade300,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: allOk
                  ? Colors.green.withOpacity(0.08)
                  : Colors.orange.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  allOk
                      ? Icons.verified_rounded
                      : Icons.admin_panel_settings_rounded,
                  color: allOk ? Colors.green[700] : Colors.orange[800],
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    allOk
                        ? 'Semua izin wajib telah diberikan'
                        : 'Izin aplikasi diperlukan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: allOk ? Colors.green[800] : Colors.orange[900],
                    ),
                  ),
                ),
                // Badge jumlah izin
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: allOk ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$grantedCount / ${perms.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Daftar izin
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: perms.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: Colors.grey[200],
            ),
            itemBuilder: (_, i) => _PermRow(
              item: perms[i],
              isLockItem: i == 2, // index 2 = Penyematan Layar
              onTap: i == 2 ? null : () => onRequest(i),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Satu baris izin ─────────────────────────────────────────

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.item,
    required this.isLockItem,
    required this.onTap,
  });

  final _PermItem item;
  final bool isLockItem;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (isLockItem) {
      statusColor = Colors.blue;
      statusIcon = Icons.info_outline_rounded;
      statusLabel = 'Saat ujian';
    } else if (item.granted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = 'Aktif';
    } else {
      statusColor = item.required ? Colors.red : Colors.orange;
      statusIcon =
          item.required ? Icons.cancel_rounded : Icons.warning_amber_rounded;
      statusLabel = item.required ? 'Diperlukan' : 'Opsional';
    }

    return InkWell(
      onTap: (!isLockItem && !item.granted) ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Ikon izin
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(item.icon, color: statusColor, size: 19),
            ),
            const SizedBox(width: 12),

            // Label & deskripsi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (item.required) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'WAJIB',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Status / tombol aktifkan
            if (item.loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (item.granted || isLockItem)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: item.required ? Colors.indigo : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Aktifkan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Sub-widget pendukung
// ============================================================

class _SchoolLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: 100,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Image.asset(
            'assets/logo_sekolah.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.school_rounded,
              size: 48,
              color: Colors.indigo,
            ),
          ),
        ),
      ),
    );
  }
}

class _LockStatusIndicator extends StatelessWidget {
  const _LockStatusIndicator({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.lock_outline : Icons.lock_open_rounded,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            isActive ? 'Sistem Terkunci & Aman' : 'Sistem Belum Terkunci',
            style: TextStyle(
              color: isActive ? Colors.green[700] : Colors.orange[800],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.isProcessing,
    required this.canStart,
    required this.onPressed,
    required this.onBlocked,
  });

  final bool isProcessing;
  final bool canStart;
  final VoidCallback onPressed;
  final VoidCallback onBlocked;

  @override
  Widget build(BuildContext context) {
    final enabled = canStart && !isProcessing;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: isProcessing ? null : (canStart ? onPressed : onBlocked),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? Colors.indigo : Colors.grey[400],
          foregroundColor: Colors.white,
          elevation: enabled ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: isProcessing
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    canStart
                        ? Icons.play_arrow_rounded
                        : Icons.lock_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    canStart ? 'MULAI UJIAN' : 'IZIN BELUM LENGKAP',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}