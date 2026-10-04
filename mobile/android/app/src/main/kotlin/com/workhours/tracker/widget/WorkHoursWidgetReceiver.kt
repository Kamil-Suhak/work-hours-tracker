package com.workhours.tracker.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.widget.RemoteViews
import com.workhours.tracker.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import android.os.Bundle
import android.view.View
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class WorkHoursWidgetReceiver : AppWidgetProvider() {

    companion object {
        const val ACTION_CLOCK_IN = "com.workhours.tracker.ACTION_CLOCK_IN"
        const val ACTION_CLOCK_OUT = "com.workhours.tracker.ACTION_CLOCK_OUT"
        const val ACTION_SYNC = "com.workhours.tracker.ACTION_SYNC"
        const val PREFS_NAME = "work_hours_widget_prefs"
        const val KEY_API_URL = "api_base_url"
        const val KEY_TOKEN = "device_token"
        const val KEY_HAPTICS = "vibrations_enabled"
        const val KEY_ACTIVE_NOTE = "active_shift_note"
        const val KEY_IS_CLOCKED_IN = "is_clocked_in"
        const val DEFAULT_API_URL = "https://work-hours-api.workers.dev"

        private val client = OkHttpClient()
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

        fun triggerHaptic(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_HAPTICS, true)) return

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    val vibrator = manager?.defaultVibrator ?: context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    val attrs = VibrationAttributes.Builder()
                        .setUsage(VibrationAttributes.USAGE_NOTIFICATION)
                        .build()
                    val effect = VibrationEffect.createOneShot(80L, 200)
                    vibrator?.vibrate(effect, attrs)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    val audioAttrs = AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .build()
                    val effect = VibrationEffect.createOneShot(80L, 200)
                    vibrator?.vibrate(effect, audioAttrs)
                } else {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(80L)
                }
            } catch (_: Exception) {}
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetView(context, appWidgetManager, appWidgetId, isClockedIn = null, syncText = "")
        }
        refreshStatusAsync(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isClockedIn = if (prefs.contains(KEY_IS_CLOCKED_IN)) prefs.getBoolean(KEY_IS_CLOCKED_IN, false) else null
        updateWidgetView(context, appWidgetManager, appWidgetId, isClockedIn, syncText = "")
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_CLOCK_IN -> {
                triggerHaptic(context)
                executeClockAction(context, "clock-in")
            }
            ACTION_CLOCK_OUT -> {
                triggerHaptic(context)
                executeClockAction(context, "clock-out")
            }
            ACTION_SYNC -> {
                triggerHaptic(context)
                refreshStatusAsync(context)
            }
        }
    }

    private fun updateWidgetView(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        isClockedIn: Boolean?,
        syncText: String = ""
    ) {
        val views = RemoteViews(context.packageName, R.layout.work_hours_widget)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Status badge configuration
        when (isClockedIn) {
            true -> {
                views.setInt(R.id.widget_status, "setBackgroundResource", R.drawable.widget_status_in)
                views.setTextColor(R.id.widget_status, Color.parseColor("#34D399"))
                views.setTextViewText(R.id.widget_status, "● CLOCKED IN")
            }
            false -> {
                views.setInt(R.id.widget_status, "setBackgroundResource", R.drawable.widget_status_out)
                views.setTextColor(R.id.widget_status, Color.parseColor("#94A3B8"))
                views.setTextViewText(R.id.widget_status, "○ CLOCKED OUT")
            }
            null -> {
                views.setInt(R.id.widget_status, "setBackgroundResource", R.drawable.widget_status_out)
                views.setTextColor(R.id.widget_status, Color.parseColor("#94A3B8"))
                views.setTextViewText(R.id.widget_status, "⋯ SYNCING")
            }
        }

        if (syncText.isNotEmpty()) {
            views.setTextViewText(R.id.widget_sync_time, "Synced $syncText")
        }

        // Responsive Notes container: show if clocked in, vertically expanded, and note exists
        val effectiveClockedIn = isClockedIn ?: prefs.getBoolean(KEY_IS_CLOCKED_IN, false)
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0
        val isExpanded = minHeight >= 100
        val activeNote = prefs.getString(KEY_ACTIVE_NOTE, "")?.trim() ?: ""

        if (effectiveClockedIn && isExpanded && activeNote.isNotEmpty()) {
            views.setViewVisibility(R.id.widget_notes_container, View.VISIBLE)
            val cleanNote = activeNote
                .lines()
                .map { line ->
                    line.trim()
                        .replace(Regex("^#+\\s*"), "")
                        .replace(Regex("^-\\s*"), "• ")
                        .replace(Regex("\\*\\*(.*?)\\*\\*"), "$1")
                        .replace(Regex("\\*(.*?)\\*"), "$1")
                }
                .filter { it.isNotEmpty() }
                .joinToString("\n")
            views.setTextViewText(R.id.widget_notes_text, cleanNote)
        } else {
            views.setViewVisibility(R.id.widget_notes_container, View.GONE)
        }

        // PendingIntent for Clock In
        val clockInIntent = Intent(context, WorkHoursWidgetReceiver::class.java).apply {
            action = ACTION_CLOCK_IN
        }
        val clockInPending = PendingIntent.getBroadcast(
            context, 101, clockInIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_clock_in, clockInPending)

        // PendingIntent for Clock Out
        val clockOutIntent = Intent(context, WorkHoursWidgetReceiver::class.java).apply {
            action = ACTION_CLOCK_OUT
        }
        val clockOutPending = PendingIntent.getBroadcast(
            context, 102, clockOutIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_clock_out, clockOutPending)

        // PendingIntent for Manual Sync button
        val syncIntent = Intent(context, WorkHoursWidgetReceiver::class.java).apply {
            action = ACTION_SYNC
        }
        val syncPending = PendingIntent.getBroadcast(
            context, 103, syncIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_sync, syncPending)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun executeClockAction(context: Context, operation: String) {
        CoroutineScope(Dispatchers.IO).launch {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val baseUrl = prefs.getString(KEY_API_URL, DEFAULT_API_URL) ?: DEFAULT_API_URL
            val token = prefs.getString(KEY_TOKEN, "") ?: ""
            val requestId = UUID.randomUUID().toString()

            val jsonBody = JSONObject().apply {
                put("requestId", requestId)
                put("source", "android_widget")
            }

            val request = Request.Builder()
                .url("$baseUrl/api/v1/$operation")
                .post(jsonBody.toString().toRequestBody(JSON_MEDIA_TYPE))
                .apply {
                    if (token.isNotEmpty()) addHeader("Authorization", "Bearer $token")
                }
                .build()

            try {
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: "{}"
                val json = JSONObject(responseBody)
                val state = json.optString("state", "unknown")
                val isClockedIn = state == "clocked_in"
                prefs.edit().putBoolean(KEY_IS_CLOCKED_IN, isClockedIn).apply()
                if (!isClockedIn) {
                    prefs.edit().putString(KEY_ACTIVE_NOTE, "").apply()
                }
                val syncTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, isClockedIn, syncTime)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, isClockedIn = null, syncText = "Err")
                }
            }
        }
    }

    private fun refreshStatusAsync(context: Context) {
        CoroutineScope(Dispatchers.IO).launch {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val baseUrl = prefs.getString(KEY_API_URL, DEFAULT_API_URL) ?: DEFAULT_API_URL
            val token = prefs.getString(KEY_TOKEN, "") ?: ""

            val request = Request.Builder()
                .url("$baseUrl/api/v1/status")
                .get()
                .apply {
                    if (token.isNotEmpty()) addHeader("Authorization", "Bearer $token")
                }
                .build()

            try {
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: "{}"
                val json = JSONObject(responseBody)
                val state = json.optString("state", "clocked_out")
                val isClockedIn = state == "clocked_in"
                prefs.edit().putBoolean(KEY_IS_CLOCKED_IN, isClockedIn).apply()
                if (!isClockedIn) {
                    prefs.edit().putString(KEY_ACTIVE_NOTE, "").apply()
                }
                val syncTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, isClockedIn, syncTime)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, isClockedIn = null, syncText = "Offline")
                }
            }
        }
    }

    private fun updateAllWidgets(context: Context, isClockedIn: Boolean?, syncText: String) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, WorkHoursWidgetReceiver::class.java))
        for (id in ids) {
            updateWidgetView(context, appWidgetManager, id, isClockedIn, syncText)
        }
    }
}
