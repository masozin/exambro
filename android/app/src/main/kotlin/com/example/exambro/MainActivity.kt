// ============================================================
// MainActivity.kt — Native Android
// Fitur: Lock Mode, DND, Audio Alert, Anti Split Screen,
//        Anti Floating Window, Anti Picture-in-Picture
// ============================================================

package com.example.exambro

import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "ExambroNative"
        private const val CHANNEL_LOCK = "exambro/lockmode"
        private const val CHANNEL_DND  = "exam.channel"
    }

    // ── State ─────────────────────────────────────────────────
    private var mediaPlayer: MediaPlayer? = null
    private var isExamRunning = false

    // ── onCreate ──────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        applySecurityFlags()
        blockFloatingWindow()
        disablePictureInPicture()
    }

    // ── Security Flags ────────────────────────────────────────

    /**
     * Terapkan semua flag keamanan window sejak aplikasi dibuka:
     * - FLAG_SECURE        : cegah screenshot & screen recording
     * - SOFT_INPUT_ADJUST_RESIZE : pastikan layout tidak bergeser saat keyboard muncul
     */
    private fun applySecurityFlags() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        Log.d(TAG, "Security flags applied")
    }

    // ── Anti Floating Window ──────────────────────────────────

    /**
     * Mencegah aplikasi tampil dalam mode floating/freeform window.
     * Pada ROM tertentu (MIUI, OneUI, ColorOS) ada fitur "layar mengambang"
     * yang memungkinkan aplikasi berjalan di jendela kecil di atas layar lain.
     *
     * Cara kerja:
     * 1. Paksa ukuran window agar selalu memenuhi layar penuh.
     * 2. Nonaktifkan resize window agar sistem tidak bisa mengubah ukurannya.
     */
    private fun blockFloatingWindow() {
        try {
            // Paksa layout fullscreen — mencegah freeform/floating mode
            val lp = window.attributes
            lp.width  = WindowManager.LayoutParams.MATCH_PARENT
            lp.height = WindowManager.LayoutParams.MATCH_PARENT
            window.attributes = lp

            // Pada Android 7+ (API 24), nonaktifkan multi-window secara eksplisit
            // via immersive sticky mode + keep screen on
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                )
            }

            Log.d(TAG, "Floating window blocked")
        } catch (e: Exception) {
            Log.e(TAG, "blockFloatingWindow error: ${e.message}")
        }
    }

    /**
     * Dipanggil sistem saat ukuran/mode window berubah (split screen, dsb).
     * Jika ukuran window tidak full, paksa kembali ke fullscreen dan bunyikan sirine.
     */
    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        Log.d(TAG, "onMultiWindowModeChanged: isMultiWindow=$isInMultiWindowMode, examRunning=$isExamRunning")

        if (isInMultiWindowMode && isExamRunning) {
            // Paksa kembali ke fullscreen
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    // Minta sistem keluar dari multi-window dengan melempar Intent baru
                    // yang menargetkan activity ini sendiri dalam mode fullscreen
                    val intent = intent
                    intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    startActivity(intent)
                    Log.d(TAG, "Forced back to fullscreen from multi-window")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to exit multi-window: ${e.message}")
                }
            }
            // Bunyikan sirine sebagai peringatan
            playAlertSound()
        } else if (!isInMultiWindowMode) {
            stopAlertSound()
        }
    }

    // ── Anti Picture-in-Picture ───────────────────────────────

    /**
     * Nonaktifkan PiP (Picture-in-Picture) agar siswa tidak bisa
     * memperkecil aplikasi menjadi jendela kecil di atas aplikasi lain.
     */
    private fun disablePictureInPicture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // Tandai activity ini tidak mendukung PiP
                setPictureInPictureParams(
                    PictureInPictureParams.Builder()
                        .build()
                )
                Log.d(TAG, "PiP disabled")
            } catch (e: Exception) {
                Log.e(TAG, "disablePictureInPicture error: ${e.message}")
            }
        }
    }

    /**
     * Dipanggil sistem saat user atau sistem mencoba masuk PiP.
     * Kita TIDAK memanggil super agar PiP tidak pernah aktif.
     */
    override fun onUserLeaveHint() {
        // Sengaja tidak memanggil super.onUserLeaveHint()
        // agar system tidak trigger PiP saat user tekan Home
        Log.d(TAG, "onUserLeaveHint intercepted — PiP blocked")
        if (isExamRunning) playAlertSound()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode && isExamRunning) {
            // Jika entah bagaimana PiP aktif, langsung keluar
            Log.w(TAG, "PiP mode detected during exam! Forcing exit.")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                moveTaskToBack(false) // paksa kembali
            }
            playAlertSound()
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "onPause — examRunning=$isExamRunning")
        if (isExamRunning) playAlertSound()
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume")
        // Re-terapkan flag keamanan (beberapa ROM me-reset flag saat resume)
        applySecurityFlags()
        blockFloatingWindow()
        stopAlertSound()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // Terapkan ulang immersive mode setiap kali window mendapat fokus
            // (misal: setelah dialog system tertutup)
            blockFloatingWindow()
        } else if (isExamRunning) {
            // Window kehilangan fokus saat ujian → ada sesuatu di depan layar
            Log.d(TAG, "Window focus lost during exam")
            playAlertSound()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlertSound()
    }

    // ── Flutter Method Channels ───────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupDndChannel(flutterEngine)
        setupLockChannel(flutterEngine)
    }

    private fun setupDndChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_DND)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkAndEnableDND" -> {
                        val openSettings = call.argument<Boolean>("openSettings") ?: true
                        result.success(checkAndEnableDnd(openSettings))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupLockChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_LOCK)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableLockMode" -> {
                        isExamRunning = true
                        enablePinnedMode()
                        result.success(true)
                    }
                    "disableLockMode" -> {
                        isExamRunning = false
                        disablePinnedMode()
                        stopAlertSound()
                        result.success(true)
                    }
                    "isLockTaskActive" -> result.success(isLockTaskActive())
                    "exitExam" -> {
                        isExamRunning = false
                        exitExam()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Lock Mode ─────────────────────────────────────────────

    private fun enablePinnedMode() {
        try {
            startLockTask()
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            Log.d(TAG, "startLockTask() requested")
        } catch (e: Exception) {
            Log.e(TAG, "enablePinnedMode error: ${e.message}")
        }
    }

    private fun disablePinnedMode() {
        try {
            stopLockTask()
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            Log.d(TAG, "stopLockTask() requested")
        } catch (e: Exception) {
            Log.e(TAG, "disablePinnedMode error: ${e.message}")
        }
    }

    private fun isLockTaskActive(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            am.isInLockTaskMode
        }
    }

    private fun exitExam() {
        stopAlertSound()
        try {
            try { stopLockTask() } catch (e: Exception) {
                Log.w(TAG, "stopLockTask in exit failed: ${e.message}")
            }
            finishAffinity()
        } catch (e: Exception) {
            Log.e(TAG, "exitExam error: ${e.message}")
        }
    }

    // ── DND ───────────────────────────────────────────────────

    private fun checkAndEnableDnd(openSettings: Boolean): Boolean {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        return if (!nm.isNotificationPolicyAccessGranted) {
            if (openSettings) {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            }
            false
        } else {
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
            true
        }
    }

    // ── Audio Alert ───────────────────────────────────────────

    private fun playAlertSound() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                try { audioManager.ringerMode = AudioManager.RINGER_MODE_NORMAL }
                catch (e: Exception) { Log.e(TAG, "Gagal ubah ringer mode: ${e.message}") }
            }

            requestAudioFocus(audioManager)

            if (mediaPlayer == null) mediaPlayer = MediaPlayer()

            if (mediaPlayer?.isPlaying == false) {
                mediaPlayer?.reset()

                val afd = resources.openRawResourceFd(R.raw.siren)
                    ?: run { Log.e(TAG, "File siren tidak ditemukan di res/raw/"); return }

                mediaPlayer?.apply {
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                            .build(),
                    )
                    isLooping = true
                    setVolume(1.0f, 1.0f)
                    prepare()

                    val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)

                    start()
                    Log.d(TAG, "Alert sound started")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "playAlertSound error: ${e.message}")
        }
    }

    private fun stopAlertSound() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            abandonAudioFocus(audioManager)
            mediaPlayer?.let { if (it.isPlaying) it.stop(); it.release() }
            mediaPlayer = null
            Log.d(TAG, "Alert sound stopped")
        } catch (e: Exception) {
            Log.e(TAG, "stopAlertSound error: ${e.message}")
        }
    }

    private fun requestAudioFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener { }
                .build()
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
        }
    }

    private fun abandonAudioFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE).build()
            audioManager.abandonAudioFocusRequest(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }
}