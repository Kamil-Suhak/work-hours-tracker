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

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.workhours.tracker/widget_sync"
    private val NOTIFICATION_CHANNEL = "com.workhours.tracker/notifications"

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
                        .putBoolean(WorkHoursWidgetReceiver.KEY_HAPTICS, vibrationsEnabled)
                        .apply()
                    WorkHoursWidgetReceiver.saveDeviceToken(applicationContext, deviceToken)

                    val isClockedIn = if (prefs.contains(WorkHoursWidgetReceiver.KEY_IS_CLOCKED_IN)) prefs.getBoolean(WorkHoursWidgetReceiver.KEY_IS_CLOCKED_IN, false) else null
                    WorkHoursWidgetReceiver.updateAllWidgets(applicationContext, isClockedIn, "")

                    result.success(true)
                }
                "getWidgetCredentials" -> {
                    val prefs = applicationContext.getSharedPreferences(
                        WorkHoursWidgetReceiver.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    val baseUrl = prefs.getString(WorkHoursWidgetReceiver.KEY_API_URL, "") ?: ""
                    val token = WorkHoursWidgetReceiver.loadDeviceToken(applicationContext)
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

                    val isClockedIn = if (prefs.contains(WorkHoursWidgetReceiver.KEY_IS_CLOCKED_IN)) prefs.getBoolean(WorkHoursWidgetReceiver.KEY_IS_CLOCKED_IN, false) else null
                    WorkHoursWidgetReceiver.updateAllWidgets(applicationContext, isClockedIn, "")
                    result.success(true)
                }
                "syncWidgetStatus" -> {
                    val isClockedIn = call.argument<Boolean>("isClockedIn") ?: false
                    val activeNote = call.argument<String?>("activeNote")
                    val syncTime = call.argument<String?>("syncTime")
                        ?: SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

                    val prefs = applicationContext.getSharedPreferences(
                        WorkHoursWidgetReceiver.PREFS_NAME,
                        Context.MODE_PRIVATE
                    )
                    val editor = prefs.edit().putBoolean(WorkHoursWidgetReceiver.KEY_IS_CLOCKED_IN, isClockedIn)
                    if (activeNote != null) {
                        editor.putString(WorkHoursWidgetReceiver.KEY_ACTIVE_NOTE, activeNote)
                    } else if (!isClockedIn) {
                        editor.putString(WorkHoursWidgetReceiver.KEY_ACTIVE_NOTE, "")
                    }
                    editor.apply()

                    WorkHoursWidgetReceiver.updateAllWidgets(applicationContext, isClockedIn, syncTime)
                    result.success(true)
                }
                "saveAndOpenReport" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val rawFilename = call.argument<String>("filename") ?: "work-hours-report.xlsx"
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Missing file bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = resolveSafeReportFile(rawFilename)
                        if (file == null) {
                            result.error("INVALID_ARGS", "Invalid report filename", null)
                            return@setMethodCallHandler
                        }
                        file.writeBytes(bytes)

                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )

                        val mimeType = if (file.name.endsWith(".docx", ignoreCase = true)) {
                            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                        } else {
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
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
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Missing file path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val reportsDir = getReportsCacheDir()
                        val canonicalDir = reportsDir.canonicalPath
                        val file = File(filePath)
                        val canonicalFile = file.canonicalPath
                        if (!canonicalFile.startsWith(canonicalDir + File.separator)) {
                            result.error("INVALID_ARGS", "Report path outside reports directory", null)
                            return@setMethodCallHandler
                        }
                        if (!file.exists() || !file.isFile) {
                            result.error("NOT_FOUND", "File does not exist", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val mimeType = if (file.name.endsWith(".docx", ignoreCase = true)) {
                            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                        } else {
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        }
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
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

        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    createNotificationChannel()
                    result.success(true)
                }
                "requestPermissions" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
                        }
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "scheduleReminder" -> {
                    try {
                        val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                            ?: (call.argument<Number>("triggerAtMillis")?.toLong() ?: 0L)
                        val title = call.argument<String>("title") ?: "Shift Ending Soon"
                        val body = call.argument<String>("body") ?: "Your planned shift ends soon. Remember to clock out!"

                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                        val intent = Intent(this, ShiftReminderReceiver::class.java).apply {
                            action = ShiftReminderReceiver.ACTION_REMINDER
                            putExtra("title", title)
                            putExtra("body", body)
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            ShiftReminderReceiver.NOTIFICATION_ID,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        if (alarmManager != null && triggerAtMillis > System.currentTimeMillis()) {
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    if (alarmManager.canScheduleExactAlarms()) {
                                        alarmManager.setExactAndAllowWhileIdle(
                                            AlarmManager.RTC_WAKEUP,
                                            triggerAtMillis,
                                            pendingIntent
                                        )
                                    } else {
                                        alarmManager.setAndAllowWhileIdle(
                                            AlarmManager.RTC_WAKEUP,
                                            triggerAtMillis,
                                            pendingIntent
                                        )
                                    }
                                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    alarmManager.setExactAndAllowWhileIdle(
                                        AlarmManager.RTC_WAKEUP,
                                        triggerAtMillis,
                                        pendingIntent
                                    )
                                } else {
                                    alarmManager.setExact(
                                        AlarmManager.RTC_WAKEUP,
                                        triggerAtMillis,
                                        pendingIntent
                                    )
                                }
                            } catch (secEx: SecurityException) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    alarmManager.setAndAllowWhileIdle(
                                        AlarmManager.RTC_WAKEUP,
                                        triggerAtMillis,
                                        pendingIntent
                                    )
                                }
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SCHEDULE_FAILED", e.localizedMessage, null)
                    }
                }
                "cancelReminder" -> {
                    try {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                        val intent = Intent(this, ShiftReminderReceiver::class.java).apply {
                            action = ShiftReminderReceiver.ACTION_REMINDER
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            ShiftReminderReceiver.NOTIFICATION_ID,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        alarmManager?.cancel(pendingIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getReportsCacheDir(): File {
        val dir = File(applicationContext.cacheDir, "reports")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun resolveSafeReportFile(rawFilename: String): File? {
        val segment = rawFilename.trim().substringAfterLast('/').substringAfterLast('\\')
        if (segment.isEmpty() || segment == "." || segment == ".." || segment.contains("..")) {
            return null
        }
        val safeName = segment.replace(Regex("[^A-Za-z0-9._-]"), "_")
        if (safeName.isEmpty() || safeName.startsWith('.')) {
            return null
        }
        val dir = getReportsCacheDir()
        val canonicalDir = dir.canonicalPath
        val candidate = File(dir, safeName)
        if (!candidate.canonicalPath.startsWith(canonicalDir + File.separator)) {
            return null
        }
        return candidate
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                ?: return
            val channel = android.app.NotificationChannel(
                ShiftReminderReceiver.CHANNEL_ID,
                "Shift Reminders",
                android.app.NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders to clock out before planned shift end"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
}
