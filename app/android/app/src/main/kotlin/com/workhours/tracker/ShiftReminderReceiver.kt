package com.workhours.tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.workhours.tracker.widget.WorkHoursWidgetReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class ShiftReminderReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "shift_reminders_channel"
        const val NOTIFICATION_ID = 1001
        const val TARGET_NOTIFICATION_ID = 1002
        const val ACTION_REMINDER = "com.workhours.tracker.ACTION_SHIFT_REMINDER"
        const val ACTION_TARGET_REACHED = "com.workhours.tracker.ACTION_SHIFT_TARGET_REACHED"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val isTargetReached = intent.action == ACTION_TARGET_REACHED
        val notificationId = if (isTargetReached) TARGET_NOTIFICATION_ID else NOTIFICATION_ID
        val title = intent.getStringExtra("title")
            ?: if (isTargetReached) "Clock-Out Target Reached" else "Shift Ending Soon"
        val body = intent.getStringExtra("body")
            ?: if (isTargetReached) {
                "Your planned clock-out target has been reached."
            } else {
                "Your planned shift ends soon. Remember to clock out!"
            }
        val targetUtcIso = intent.getStringExtra("targetUtcIso")

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val shouldNotify = checkServerAllowsNotification(
                    context = context,
                    isTargetReached = isTargetReached,
                    targetUtcIso = targetUtcIso,
                )
                if (shouldNotify) {
                    showNotification(context, notificationId, title, body)
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    /**
     * Polls GET /api/v1/status to ensure the user is still clocked in (or was
     * just auto-stopped at target) before firing a local notification.
     */
    private fun checkServerAllowsNotification(
        context: Context,
        isTargetReached: Boolean,
        targetUtcIso: String?,
    ): Boolean {
        val prefs = context.getSharedPreferences(WorkHoursWidgetReceiver.PREFS_NAME, Context.MODE_PRIVATE)
        val baseUrl = prefs.getString(WorkHoursWidgetReceiver.KEY_API_URL, null)?.trim()
        val token = WorkHoursWidgetReceiver.loadDeviceToken(context)

        if (baseUrl.isNullOrEmpty() || token.isEmpty()) {
            return !isTargetReached
        }

        val normalizedBase = if (baseUrl.endsWith("/")) baseUrl.dropLast(1) else baseUrl
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL("$normalizedBase/api/v1/status").openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
                setRequestProperty("Authorization", "Bearer $token")
            }
            if (conn.responseCode != 200) {
                return !isTargetReached
            }
            val raw = conn.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(raw)
            val state = json.optString("state", "")
            if (state == "clocked_in") {
                return true
            }
            if (!isTargetReached) {
                // Already clocked out before pre-end reminder
                return false
            }

            // Target-reached: GET /api/v1/status materializes auto-stop at target.
            // Only notify if the latest event is a clock_out at/after targetUtcIso
            // created within the last 5 minutes (not a manual clock-out from earlier).
            val latest = json.optJSONObject("latestEvent") ?: return false
            if (latest.optString("eventType", "") != "clock_out") return false

            val occurredMs = parseIsoUtcMillis(latest.optString("occurredAtUtc", "")) ?: return false
            val createdMs = parseIsoUtcMillis(latest.optString("createdAtUtc", "")) ?: return false
            val targetMs = parseIsoUtcMillis(targetUtcIso ?: "") ?: return false
            val targetMinuteMs = (targetMs / 60_000L) * 60_000L

            if (occurredMs < targetMinuteMs) return false
            kotlin.math.abs(System.currentTimeMillis() - createdMs) <= 5 * 60_000L
        } catch (_: Exception) {
            !isTargetReached
        } finally {
            conn?.disconnect()
        }
    }

    private fun parseIsoUtcMillis(iso: String): Long? {
        if (iso.isBlank()) return null
        val normalized = iso.trim()
        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSX",
            "yyyy-MM-dd'T'HH:mm:ssX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
        )
        for (pattern in patterns) {
            try {
                val fmt = SimpleDateFormat(pattern, Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val date = fmt.parse(normalized)
                if (date != null) return date.time
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun showNotification(
        context: Context,
        notificationId: Int,
        title: String,
        body: String,
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Shift Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders to clock out before or at planned shift end"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(notificationId, notification)
    }
}
