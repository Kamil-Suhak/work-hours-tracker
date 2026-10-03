package com.workhours.tracker.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class WorkHoursWidgetReceiver : AppWidgetProvider() {

    companion object {
        const val ACTION_CLOCK_IN = "com.workhours.tracker.ACTION_CLOCK_IN"
        const val ACTION_CLOCK_OUT = "com.workhours.tracker.ACTION_CLOCK_OUT"
        const val PREFS_NAME = "work_hours_widget_prefs"
        const val KEY_API_URL = "api_base_url"
        const val KEY_TOKEN = "device_token"
        const val DEFAULT_API_URL = "https://work-hours-api.workers.dev"

        private val client = OkHttpClient()
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetView(context, appWidgetManager, appWidgetId)
        }
        refreshStatusAsync(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_CLOCK_IN -> executeClockAction(context, "clock-in")
            ACTION_CLOCK_OUT -> executeClockAction(context, "clock-out")
        }
    }

    private fun updateWidgetView(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        statusText: String = "Loading...",
        syncText: String = ""
    ) {
        val views = RemoteViews(context.packageName, R.layout.work_hours_widget)
        views.setTextViewText(R.id.widget_status, statusText)
        if (syncText.isNotEmpty()) {
            views.setTextViewText(R.id.widget_sync_time, "Last synced: $syncText")
        }

        // Set pending intents for buttons
        val clockInIntent = Intent(context, WorkHoursWidgetReceiver::class.java).apply {
            action = ACTION_CLOCK_IN
        }
        val clockInPending = PendingIntent.getBroadcast(
            context, 101, clockInIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_clock_in, clockInPending)

        val clockOutIntent = Intent(context, WorkHoursWidgetReceiver::class.java).apply {
            action = ACTION_CLOCK_OUT
        }
        val clockOutPending = PendingIntent.getBroadcast(
            context, 102, clockOutIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.btn_clock_out, clockOutPending)

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
                val syncTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
                val displayStatus = if (isClockedIn) "Clocked in" else "Clocked out"

                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, "Status: $displayStatus", syncTime)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, "Status: Network Error", "")
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
                val syncTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
                val displayStatus = if (isClockedIn) "Clocked in" else "Clocked out"

                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, "Status: $displayStatus", syncTime)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    updateAllWidgets(context, "Status: Offline", "")
                }
            }
        }
    }

    private fun updateAllWidgets(context: Context, statusText: String, syncText: String) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, WorkHoursWidgetReceiver::class.java))
        for (id in ids) {
            updateWidgetView(context, appWidgetManager, id, statusText, syncText)
        }
    }
}
