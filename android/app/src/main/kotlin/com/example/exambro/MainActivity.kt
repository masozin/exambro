package com.example.exambro

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import android.app.NotificationManager
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.media.MediaPlayer
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioFocusRequest // Tambahan untuk Android O+

class MainActivity : FlutterActivity() {

    // Variable untuk player suara
    private var mediaPlayer: MediaPlayer? = null
    // Flag untuk menandakan ujian sedang aktif atau tidak
    private var isExamRunning = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Mencegah screenshot/record screen
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "exam.channel")
            .setMethodCallHandler { call, result ->
                if (call.method == "checkAndEnableDND") {
                    val isGranted = checkAndEnableDND()
                    result.success(isGranted)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "exambro/lockmode")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableLockMode" -> {
                        isExamRunning = true // Tandai ujian mulai
                        enablePinnedMode()
                        result.success(true)
                    }
                    "disableLockMode" -> {
                        isExamRunning = false // Tandai ujian selesai
                        disablePinnedMode()
                        stopAlertSound() // Pastikan suara mati
                        result.success(true)
                    }
                    "isLockTaskActive" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val isActive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val state = am.lockTaskModeState
                            state != ActivityManager.LOCK_TASK_MODE_NONE
                        } else {
                            @Suppress("DEPRECATION")
                            am.isInLockTaskMode
                        }
                        result.success(isActive)
                    }
                    "exitExam" -> {
                        isExamRunning = false
                        exitExam()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- LIFECYCLE HANDLERS ---
    
    // Dipanggil saat user minimize aplikasi, tekan home, atau switch app
    override fun onPause() {
        super.onPause()
        Log.d("ExambroNative", "onPause Detected. ExamRunning: $isExamRunning")
        
        // Jika ujian sedang berjalan dan aplikasi di-minimize/background
        if (isExamRunning) {
            playAlertSound()
        }
    }

    // Dipanggil saat user kembali ke aplikasi
    override fun onResume() {
        super.onResume()
        Log.d("ExambroNative", "onResume Detected.")
        // Matikan suara saat user kembali
        stopAlertSound()
    }
    
    // --- AUDIO LOGIC (CUSTOM SOUND) ---

    private fun playAlertSound() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // 1. FORCE RINGER MODE NORMAL (Agar tidak silent)
            if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                try {
                   audioManager.ringerMode = AudioManager.RINGER_MODE_NORMAL
                } catch (e: Exception) {
                   Log.e("ExambroNative", "Gagal ubah ringer mode: ${e.message}")
                }
            }

            // 2. REQUEST AUDIO FOCUS (PENTING AGAR BUNYI DI BACKGROUND)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener { /* Listener kosong, kita handle logic sendiri */ }
                    .build()
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
                )
            }

            // 3. SETUP PLAYER
            if (mediaPlayer == null) {
                mediaPlayer = MediaPlayer()
            }

            if (mediaPlayer?.isPlaying == false) {
                mediaPlayer?.reset() 
                
                val afd = resources.openRawResourceFd(R.raw.siren)
                if (afd == null) {
                     Log.e("ExambroNative", "File suara tidak ditemukan di raw/siren")
                     return
                }

                mediaPlayer?.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()

                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                    .build()
                    
                mediaPlayer?.setAudioAttributes(audioAttributes)
                mediaPlayer?.isLooping = true 
                mediaPlayer?.setVolume(1.0f, 1.0f) // Pastikan volume player MAX
                mediaPlayer?.prepare() 

                // 4. FORCE DEVICE VOLUME MAX
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)

                mediaPlayer?.start()
                Log.d("ExambroNative", "Custom Siren Sound Started with Audio Focus")
            }
        } catch (e: Exception) {
            Log.e("ExambroNative", "Error playing custom sound: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun stopAlertSound() {
        try {
            // Lepaskan Audio Focus saat suara berhenti
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE).build()
                audioManager.abandonAudioFocusRequest(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }

            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release() 
            }
            mediaPlayer = null
        } catch (e: Exception) {
            Log.e("ExambroNative", "Error stopping sound: ${e.message}")
        }
    }
    
    // --- EXISTING METHODS ---

    private fun enablePinnedMode() {
        try {
            startLockTask()
            Log.d("ExambroNative", "Requesting startLockTask()")
        } catch (e: Exception) {
            Log.e("ExambroNative", "Failed to Request Lock Mode: ${e.message}")
        }
    }

    private fun disablePinnedMode() {
        try {
            stopLockTask()
            Log.d("ExambroNative", "Requesting stopLockTask()")
        } catch (e: Exception) {
            Log.e("ExambroNative", "Failed to Disable Lock Mode: ${e.message}")
        }
    }

    private fun checkAndEnableDND(): Boolean {
        val notificationManager =
            getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        if (!notificationManager.isNotificationPolicyAccessGranted) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            startActivity(intent)
            return false 
        } else {
            // PERBAIKAN: Gunakan INTERRUPTION_FILTER_ALARMS agar Alarm tetap bunyi
            // INTERRUPTION_FILTER_NONE = Blokir TOTAL (termasuk alarm di beberapa HP)
            // INTERRUPTION_FILTER_ALARMS = Blokir Telepon/WA tapi Alarm JALAN.
            notificationManager.setInterruptionFilter(
                NotificationManager.INTERRUPTION_FILTER_ALARMS
            )
            return true 
        }
    }

    private fun exitExam() {
        stopAlertSound() // Safety stop
        try {
            try {
                stopLockTask()
            } catch (inner: Exception) {
                Log.w("ExambroNative", "stopLockTask failed: ${inner.message}")
            }
            finishAffinity() 
        } catch (e: Exception) {
            Log.e("ExambroNative", "Failed exitExam: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopAlertSound()
    }
}