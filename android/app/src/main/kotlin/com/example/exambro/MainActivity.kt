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

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "exam.channel")
            .setMethodCallHandler { call, result ->
                if (call.method == "enableDND") {
                    enableDoNotDisturb()
                    result.success("done")
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
            Log.d("LockMode", "Lock Mode Enabled")
        } catch (e: Exception) {
            e.printStackTrace()
            Log.e("LockMode", "Failed to Enable Lock Mode: ${e.message}")
        }
    }

    private fun disablePinnedMode() {
        try {
            stopLockTask()
            Log.d("LockMode", "Lock Mode Disabled, attempting exit.")
        } catch (e: Exception) {
            e.printStackTrace()
            Log.e("LockMode", "Failed to Disable Lock Mode: ${e.message}")
        }
    }

    private fun enableDoNotDisturb() {
        val notificationManager =
            getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        if (!notificationManager.isNotificationPolicyAccessGranted) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            startActivity(intent)
        } else {
            notificationManager.setInterruptionFilter(
                NotificationManager.INTERRUPTION_FILTER_NONE
            )
        }
    }

    private fun exitExam() {
        try {
            // Pastikan lepaskan lock task dulu, lalu keluar aplikasi
            try {
                stopLockTask()
            } catch (inner: Exception) {
                Log.w("Exambro", "stopLockTask failed: ${inner.message}")
            }
            finishAffinity()
            Log.d("Exambro", "exitExam executed")
        } catch (e: Exception) {
            Log.e("Exambro", "Failed exitExam: ${e.message}")
        }
    }
}
