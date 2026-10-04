package com.workhours.tracker

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import com.workhours.tracker.widget.WorkHoursWidgetReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.workhours.tracker/widget_sync"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val manager = applicationContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                            val vibrator = manager?.defaultVibrator ?: applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                            val attrs = VibrationAttributes.Builder()
                                .setUsage(VibrationAttributes.USAGE_NOTIFICATION)
                                .build()
                            val effect = VibrationEffect.createOneShot(80L, 200)
                            vibrator?.vibrate(effect, attrs)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val vibrator = applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                            val audioAttrs = AudioAttributes.Builder()
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                                .build()
                            val effect = VibrationEffect.createOneShot(80L, 200)
                            vibrator?.vibrate(effect, audioAttrs)
                        } else {
                            @Suppress("DEPRECATION")
                            val vibrator = applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                            @Suppress("DEPRECATION")
                            vibrator?.vibrate(80L)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "syncWidgetCredentials" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: ""
                    val deviceToken = call.argument<String>("deviceToken") ?: ""
                    val vibrationsEnabled = call.argument<Boolean>("vibrationsEnabled") ?: true

                    val prefs = applicationContext.getSharedPreferences(
                        WorkHoursWidgetReceiver.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    prefs.edit()
                        .putString(WorkHoursWidgetReceiver.KEY_API_URL, baseUrl)
                        .putString(WorkHoursWidgetReceiver.KEY_TOKEN, deviceToken)
                        .putBoolean(WorkHoursWidgetReceiver.KEY_HAPTICS, vibrationsEnabled)
                        .apply()

                    // Trigger widget update broadcast so widget re-renders with new credentials
                    val intent = Intent(applicationContext, WorkHoursWidgetReceiver::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
                        val ids = appWidgetManager.getAppWidgetIds(
                            ComponentName(applicationContext, WorkHoursWidgetReceiver::class.java)
                        )
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    applicationContext.sendBroadcast(intent)

                    result.success(true)
                }
                "getWidgetCredentials" -> {
                    val prefs = applicationContext.getSharedPreferences(
                        WorkHoursWidgetReceiver.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    val baseUrl = prefs.getString(WorkHoursWidgetReceiver.KEY_API_URL, "") ?: ""
                    val token = prefs.getString(WorkHoursWidgetReceiver.KEY_TOKEN, "") ?: ""
                    val vibrationsEnabled = prefs.getBoolean(WorkHoursWidgetReceiver.KEY_HAPTICS, true)
                    result.success(mapOf("baseUrl" to baseUrl, "deviceToken" to token, "vibrationsEnabled" to vibrationsEnabled))
                }
                "syncActiveNote" -> {
                    val note = call.argument<String>("note") ?: ""
                    val prefs = applicationContext.getSharedPreferences(
                        WorkHoursWidgetReceiver.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    prefs.edit().putString(WorkHoursWidgetReceiver.KEY_ACTIVE_NOTE, note).apply()

                    val intent = Intent(applicationContext, WorkHoursWidgetReceiver::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
                        val ids = appWidgetManager.getAppWidgetIds(
                            ComponentName(applicationContext, WorkHoursWidgetReceiver::class.java)
                        )
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    applicationContext.sendBroadcast(intent)
                    result.success(true)
                }
                "saveAndOpenReport" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val filename = call.argument<String>("filename") ?: "work-hours-report.xlsx"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing file bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val dir = File(applicationContext.cacheDir, "reports")
                        if (!dir.exists()) dir.mkdirs()
                        val file = File(dir, filename)
                        file.writeBytes(bytes)

                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        applicationContext.startActivity(intent)
                        result.success(file.absolutePath)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.localizedMessage, null)
                    }
                }
                "openReportFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "Missing file path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "File does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        applicationContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
