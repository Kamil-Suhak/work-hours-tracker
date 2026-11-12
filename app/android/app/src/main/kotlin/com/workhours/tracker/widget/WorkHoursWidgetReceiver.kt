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
import android.content.BroadcastReceiver.PendingResult
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class WorkHoursWidgetReceiver : AppWidgetProvider() {

    companion object {
        const val ACTION_CLOCK_IN = "com.workhours.tracker.ACTION_CLOCK_IN"
        const val ACTION_CLOCK_OUT = "com.workhours.tracker.ACTION_CLOCK_OUT"
        const val ACTION_SYNC = "com.workhours.tracker.ACTION_SYNC"
        const val PREFS_NAME = "work_hours_widget_prefs"
        const val KEY_API_URL = "api_base_url"
        const val KEY_TOKEN = "device_token"
        const val KEY_TOKEN_ENCRYPTED = "device_token_enc"
        const val KEY_HAPTICS = "vibrations_enabled"
        const val KEY_ACTIVE_NOTE = "active_shift_note"
        const val KEY_IS_CLOCKED_IN = "is_clocked_in"
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEYSTORE_ALIAS = "work_hours_widget_token_key"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_LENGTH_BITS = 128

        private val client = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .writeTimeout(5, TimeUnit.SECONDS)
            .callTimeout(8, TimeUnit.SECONDS)
            .build()
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val keystoreLock = Any()

        private fun getOrCreateTokenKey(): SecretKey {
            synchronized(keystoreLock) {
                val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
                val existing = keyStore.getKey(KEYSTORE_ALIAS, null) as? SecretKey
                if (existing != null) return existing

                val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
                val spec = KeyGenParameterSpec.Builder(
                    KEYSTORE_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
                keyGenerator.init(spec)
                return keyGenerator.generateKey()
            }
        }

        fun saveDeviceToken(context: Context, token: String) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val trimmed = token.trim()
            if (trimmed.isEmpty()) {
                prefs.edit()
                    .remove(KEY_TOKEN_ENCRYPTED)
                    .remove(KEY_TOKEN)
                    .apply()
                return
            }

            val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateTokenKey())
            val encrypted = cipher.doFinal(trimmed.toByteArray(Charsets.UTF_8))
            val ivBase64 = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
            val cipherBase64 = Base64.encodeToString(encrypted, Base64.NO_WRAP)

            prefs.edit()
                .putString(KEY_TOKEN_ENCRYPTED, "$ivBase64:$cipherBase64")
                .remove(KEY_TOKEN)
                .apply()
        }

        fun loadDeviceToken(context: Context): String {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val encryptedPayload = prefs.getString(KEY_TOKEN_ENCRYPTED, null)
            if (!encryptedPayload.isNullOrBlank()) {
                val parts = encryptedPayload.split(":", limit = 2)
                if (parts.size == 2) {
                    try {
                        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
                        val cipherBytes = Base64.decode(parts[1], Base64.NO_WRAP)
                        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
                        cipher.init(
                            Cipher.DECRYPT_MODE,
                            getOrCreateTokenKey(),
                            GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
                        )
                        return String(cipher.doFinal(cipherBytes), Charsets.UTF_8)
                    } catch (_: Exception) {
                        return ""
                    }
                }
                return ""
            }

            val legacyToken = prefs.getString(KEY_TOKEN, null)?.trim()
            if (!legacyToken.isNullOrEmpty()) {
                runCatching { saveDeviceToken(context, legacyToken) }
                return legacyToken
            }
            return ""
        }

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
        fun updateAllWidgets(context: Context, isClockedIn: Boolean?, syncText: String) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(ComponentName(context, WorkHoursWidgetReceiver::class.java))
            for (id in ids) {
                updateWidgetView(context, appWidgetManager, id, isClockedIn, syncText)
            }
        }

        fun updateWidgetView(
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
                val displayText = if (syncText == "Setup") "Setup in App" else "Synced $syncText"
                views.setTextViewText(R.id.widget_sync_time, displayText)
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
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetView(context, appWidgetManager, appWidgetId, isClockedIn = null, syncText = "")
        }
        val pendingResult = goAsync()
        refreshStatusAsync(context, pendingResult)
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
                executeClockAction(context, "clock-in", goAsync())
            }
            ACTION_CLOCK_OUT -> {
                triggerHaptic(context)
                executeClockAction(context, "clock-out", goAsync())
            }
            ACTION_SYNC -> {
                triggerHaptic(context)
                refreshStatusAsync(context, goAsync())
            }
        }
    }

    private fun executeClockAction(context: Context, operation: String, pendingResult: PendingResult?) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val baseUrl = prefs.getString(KEY_API_URL, null)?.trim()
                val token = loadDeviceToken(context)

                if (baseUrl.isNullOrEmpty() || token.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        updateAllWidgets(context, isClockedIn = null, syncText = "Setup")
                    }
                    return@launch
                }
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
                    client.newCall(request).execute().use { response ->
                        handleWidgetStateResponse(context, prefs, response, errorSyncText = "Err")
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        updateAllWidgets(context, isClockedIn = null, syncText = "Err")
                    }
                }
            } finally {
                runCatching { pendingResult?.finish() }
            }
        }
    }

    private suspend fun handleWidgetStateResponse(
        context: Context,
        prefs: android.content.SharedPreferences,
        response: okhttp3.Response,
        errorSyncText: String
    ) {
        val responseBody = response.body?.string()
        if (!response.isSuccessful || responseBody.isNullOrBlank()) {
            withContext(Dispatchers.Main) {
                updateAllWidgets(context, isClockedIn = null, syncText = errorSyncText)
            }
            return
        }

        val json = JSONObject(responseBody)
        if (!json.has("state")) {
            withContext(Dispatchers.Main) {
                updateAllWidgets(context, isClockedIn = null, syncText = errorSyncText)
            }
            return
        }

        val state = json.optString("state", "")
        if (state != "clocked_in" && state != "clocked_out") {
            withContext(Dispatchers.Main) {
                updateAllWidgets(context, isClockedIn = null, syncText = errorSyncText)
            }
            return
        }

        val isClockedIn = state == "clocked_in"
        prefs.edit().putBoolean(KEY_IS_CLOCKED_IN, isClockedIn).apply()
        if (!isClockedIn) {
            prefs.edit().putString(KEY_ACTIVE_NOTE, "").apply()
        }
        val syncTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

        withContext(Dispatchers.Main) {
            updateAllWidgets(context, isClockedIn, syncTime)
        }
    }

    private fun refreshStatusAsync(context: Context, pendingResult: PendingResult?) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val baseUrl = prefs.getString(KEY_API_URL, null)?.trim()
                val token = loadDeviceToken(context)

                if (baseUrl.isNullOrEmpty() || token.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        updateAllWidgets(context, isClockedIn = null, syncText = "Setup")
                    }
                    return@launch
                }

                val request = Request.Builder()
                    .url("$baseUrl/api/v1/status")
                    .get()
                    .apply {
                        if (token.isNotEmpty()) addHeader("Authorization", "Bearer $token")
                    }
                    .build()

                try {
                    client.newCall(request).execute().use { response ->
                        handleWidgetStateResponse(context, prefs, response, errorSyncText = "Err")
                    }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        updateAllWidgets(context, isClockedIn = null, syncText = "Offline")
                    }
                }
            } finally {
                runCatching { pendingResult?.finish() }
            }
        }
    }
}
