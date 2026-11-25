package com.example.scroll_lock

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.scroll_lock/channel"

    override fun onResume() {
        super.onResume()
        ScrollLockAccessibilityService.instance?.dismissAllOverlaysForApp()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStats" -> {
                    ScrollLockAccessibilityService.checkDailyReset(this)
                    val prefs = ScrollLockAccessibilityService.getPrefs(this)
                    val count = prefs.getInt(ScrollLockAccessibilityService.KEY_SCROLL_COUNT, 0)
                    val limit = prefs.getInt(ScrollLockAccessibilityService.KEY_SCROLL_LIMIT, ScrollLockAccessibilityService.DEFAULT_LIMIT)
                    val lastDate = prefs.getString(
                        ScrollLockAccessibilityService.KEY_LAST_RESET_DATE,
                        SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                    ) ?: ""
                    val resetLimitDaily = prefs.getBoolean(ScrollLockAccessibilityService.KEY_RESET_LIMIT_DAILY, false)

                    val stats = mapOf(
                        "scrollCount" to count,
                        "scrollLimit" to limit,
                        "lastResetDate" to lastDate,
                        "isAccessibilityEnabled" to isAccessibilityServiceEnabled(),
                        "hasOverlayPermission" to hasOverlayPermission(),
                        "isLocked" to (count >= limit),
                        "resetLimitDaily" to resetLimitDaily
                    )
                    result.success(stats)
                }

                "setScrollLimit" -> {
                    val limit = call.argument<Int>("limit") ?: ScrollLockAccessibilityService.DEFAULT_LIMIT
                    val prefs = ScrollLockAccessibilityService.getPrefs(this)
                    prefs.edit().putInt(ScrollLockAccessibilityService.KEY_SCROLL_LIMIT, limit).apply()
                    ScrollLockAccessibilityService.instance?.syncState()
                    result.success(true)
                }

                "setResetLimitDaily" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val prefs = ScrollLockAccessibilityService.getPrefs(this)
                    prefs.edit().putBoolean(ScrollLockAccessibilityService.KEY_RESET_LIMIT_DAILY, enabled).apply()
                    result.success(true)
                }

                "resetScrollCount" -> {
                    val prefs = ScrollLockAccessibilityService.getPrefs(this)
                    prefs.edit().putInt(ScrollLockAccessibilityService.KEY_SCROLL_COUNT, 0).apply()
                    ScrollLockAccessibilityService.instance?.syncState()
                    result.success(true)
                }

                "simulateScroll" -> {
                    val prefs = ScrollLockAccessibilityService.getPrefs(this)
                    var count = prefs.getInt(ScrollLockAccessibilityService.KEY_SCROLL_COUNT, 0)
                    count++
                    prefs.edit().putInt(ScrollLockAccessibilityService.KEY_SCROLL_COUNT, count).apply()
                    ScrollLockAccessibilityService.instance?.syncState()
                    result.success(count)
                }

                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }

                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }

                "openInstagram" -> {
                    val launchIntent = packageManager.getLaunchIntentForPackage("com.instagram.android")
                        ?: packageManager.getLaunchIntentForPackage("com.instagram.lite")

                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launchIntent)
                        result.success(true)
                    } else {
                        // Open instagram web in browser
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.instagram.com")).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(browserIntent)
                        result.success(false)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        if (ScrollLockAccessibilityService.instance != null) {
            return true
        }
        val expectedService = ComponentName(this, ScrollLockAccessibilityService::class.java).flattenToString()
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        while (splitter.hasNext()) {
            val service = splitter.next()
            if (service.equals(expectedService, ignoreCase = true) ||
                service.contains(ScrollLockAccessibilityService::class.java.simpleName)) {
                return true
            }
        }
        return false
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
}
