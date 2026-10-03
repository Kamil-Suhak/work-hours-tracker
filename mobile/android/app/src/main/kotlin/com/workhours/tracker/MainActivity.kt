package com.workhours.tracker

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import com.workhours.tracker.widget.WorkHoursWidgetReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.workhours.tracker/widget_sync"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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
                else -> result.notImplemented()
            }
        }
    }
}
