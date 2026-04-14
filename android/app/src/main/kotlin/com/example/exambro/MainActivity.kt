// ============================================================
// MainActivity.kt — Native Android: Lock Mode, DND, Audio Alert
// ============================================================

package com.example.exambro

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
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

    // ── Lifecycle ─────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cegah screenshot & screen recording
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "onPause — examRunning=$isExamRunning")
        if (isExamRunning) playAlertSound()
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume")
        stopAlertSound()
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

    /**
     * Cek & aktifkan Do Not Disturb.
     * [openSettings] = true → buka halaman pengaturan jika belum ada izin.
     * Kembalikan true jika izin sudah granted dan DND berhasil diaktifkan.
     */
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

            // 1. Paksa ringer mode normal
            if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                try {
                    audioManager.ringerMode = AudioManager.RINGER_MODE_NORMAL
                } catch (e: Exception) {
                    Log.e(TAG, "Gagal ubah ringer mode: ${e.message}")
                }
            }

            // 2. Request audio focus
            requestAudioFocus(audioManager)

            // 3. Setup MediaPlayer
            if (mediaPlayer == null) mediaPlayer = MediaPlayer()

            if (mediaPlayer?.isPlaying == false) {
                mediaPlayer?.reset()

                val afd = resources.openRawResourceFd(R.raw.siren)
                    ?: run {
                        Log.e(TAG, "File siren tidak ditemukan di res/raw/")
                        return
                    }

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

                    // 4. Paksa volume alarm ke maksimum
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

            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
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
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
            )
        }
    }

    private fun abandonAudioFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .build()
            audioManager.abandonAudioFocusRequest(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }
}