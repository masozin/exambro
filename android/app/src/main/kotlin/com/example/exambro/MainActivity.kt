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

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Mencegah screenshot/record screen (Opsional, sesuaikan kebutuhan)
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
                    // Mengembalikan true jika sudah diizinkan, false jika belum (dan membuka settings)
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
                        enablePinnedMode()
                        result.success(true)
                    }
                    "disableLockMode" -> {
                        disablePinnedMode()
                        result.success(true)
                    }
                    "isLockTaskActive" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        
                        // --- PERBAIKAN DI SINI ---
                        val isActive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            // Mengambil status integer (0=NONE, 1=LOCKED, 2=PINNED)
                            val state = am.lockTaskModeState
                            Log.d("ExambroNative", "Current Lock State Integer: $state")
                            
                            // Kita anggap aktif jika statusnya TIDAK NONE (berarti bisa LOCKED atau PINNED)
                            state != ActivityManager.LOCK_TASK_MODE_NONE
                        } else {
                            @Suppress("DEPRECATION")
                            am.isInLockTaskMode
                        }
                        
                        Log.d("ExambroNative", "isLockTaskActive Returning: $isActive")
                        result.success(isActive)
                    }
                    "exitExam" -> {
                        exitExam()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

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

    // Mengembalikan Boolean: True jika akses diberikan, False jika membuka pengaturan
    private fun checkAndEnableDND(): Boolean {
        val notificationManager =
            getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        if (!notificationManager.isNotificationPolicyAccessGranted) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            startActivity(intent)
            return false // Izin belum ada, user diarahkan ke settings
        } else {
            notificationManager.setInterruptionFilter(
                NotificationManager.INTERRUPTION_FILTER_NONE
            )
            return true // Izin sudah ada dan mode aktif
        }
    }

    private fun exitExam() {
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
}