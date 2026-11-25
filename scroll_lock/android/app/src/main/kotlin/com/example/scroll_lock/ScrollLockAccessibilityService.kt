package com.example.scroll_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class ScrollLockAccessibilityService : AccessibilityService() {

    companion object {
        const val PREFS_NAME = "scroll_lock_preferences"
        const val KEY_SCROLL_COUNT = "scroll_count"
        const val KEY_SCROLL_LIMIT = "scroll_limit"
        const val KEY_LAST_RESET_DATE = "last_reset_date"
        const val KEY_RESET_LIMIT_DAILY = "reset_limit_daily"
        const val DEFAULT_LIMIT = 5

        @SuppressLint("StaticFieldLeak")
        var instance: ScrollLockAccessibilityService? = null

        fun checkDailyReset(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val lastDate = prefs.getString(KEY_LAST_RESET_DATE, null)
            if (today != lastDate) {
                val editor = prefs.edit()
                editor.putString(KEY_LAST_RESET_DATE, today)
                editor.putInt(KEY_SCROLL_COUNT, 0)
                if (prefs.getBoolean(KEY_RESET_LIMIT_DAILY, false)) {
                    editor.putInt(KEY_SCROLL_LIMIT, DEFAULT_LIMIT)
                }
                editor.apply()
                return true
            }
            return false
        }

        fun getPrefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        fun isInstagramPackage(pkg: String?): Boolean {
            if (pkg == null) return false
            val lower = pkg.lowercase(Locale.ROOT)
            return lower == "com.instagram.android" ||
                    lower == "com.instagram.lite" ||
                    lower.startsWith("com.instagram.") ||
                    lower.contains("instagram")
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingOverlayView: View? = null
    private var lockOverlayView: View? = null
    private var floatingParams: WindowManager.LayoutParams? = null
    private var lockParams: WindowManager.LayoutParams? = null

    private var isFloatingOverlayVisible = false
    private var isLockOverlayVisible = false

    private var lastScrollTimestamp = 0L
    private val scrollDebounceMs = 500L
    private var lockExitCooldownUntil = 0L

    private var isInstagramActive = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val watchdogHandler = Handler(Looper.getMainLooper())
    private val watchdogRunnable = object : Runnable {
        override fun run() {
            checkCurrentAppState()
            watchdogHandler.postDelayed(this, 500)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.packageNames = arrayOf("com.instagram.android", "com.instagram.lite")
        info.eventTypes = AccessibilityEvent.TYPE_VIEW_SCROLLED or AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 50
        info.flags = AccessibilityServiceInfo.FLAG_DEFAULT or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info

        checkDailyReset(this)
        startWatchdog()
    }

    fun dismissAllOverlaysForApp() {
        mainHandler.post {
            isInstagramActive = false
            hideLockOverlay()
            hideFloatingOverlay()
        }
    }

    private fun startWatchdog() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
        watchdogHandler.post(watchdogRunnable)
    }

    private fun stopWatchdog() {
        watchdogHandler.removeCallbacks(watchdogRunnable)
    }

    private fun getActivePackageName(): String? {
        return try {
            rootInActiveWindow?.packageName?.toString()
        } catch (e: Exception) {
            null
        }
    }

    private fun isTransientKeyboard(pkg: String): Boolean {
        val lower = pkg.lowercase(Locale.ROOT)
        return lower.contains("inputmethod") ||
                lower.contains("keyboard") ||
                lower.contains("ime")
    }

    private fun checkCurrentAppState() {
        val now = SystemClock.uptimeMillis()
        if (now < lockExitCooldownUntil) {
            hideLockOverlay()
            hideFloatingOverlay()
            return
        }

        val activePkg = getActivePackageName()

        // If the active package is ScrollLock itself, immediately dismiss all overlays
        if (activePkg != null && activePkg.equals(packageName, ignoreCase = true)) {
            isInstagramActive = false
            hideFloatingOverlay()
            hideLockOverlay()
            return
        }

        if (activePkg != null && isInstagramPackage(activePkg)) {
            isInstagramActive = true
            checkDailyReset(this)
            val prefs = getPrefs(this)
            val count = prefs.getInt(KEY_SCROLL_COUNT, 0)
            val limit = prefs.getInt(KEY_SCROLL_LIMIT, DEFAULT_LIMIT)
            if (count >= limit) {
                hideFloatingOverlay()
                showLockOverlay(count, limit)
            } else {
                hideLockOverlay()
                showFloatingOverlay(count, limit)
            }
        } else {
            // Keep state only if keyboard is currently up inside Instagram
            if (activePkg != null && isTransientKeyboard(activePkg) && isInstagramActive) {
                return
            }
            // In all other cases (e.g. Home screen, GPay, other apps), ensure overlays are strictly removed
            isInstagramActive = false
            hideFloatingOverlay()
            hideLockOverlay()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val pkgName = event.packageName?.toString() ?: getActivePackageName() ?: return

        // If event is from ScrollLock itself, remove overlays
        if (pkgName.equals(packageName, ignoreCase = true)) {
            isInstagramActive = false
            mainHandler.post {
                hideFloatingOverlay()
                hideLockOverlay()
            }
            return
        }

        val isInstagram = isInstagramPackage(pkgName)

        if (isInstagram) {
            val now = SystemClock.uptimeMillis()
            if (now < lockExitCooldownUntil) {
                return
            }

            isInstagramActive = true
            checkDailyReset(this)
            val prefs = getPrefs(this)
            var count = prefs.getInt(KEY_SCROLL_COUNT, 0)
            val limit = prefs.getInt(KEY_SCROLL_LIMIT, DEFAULT_LIMIT)

            if (count >= limit) {
                mainHandler.post {
                    hideFloatingOverlay()
                    showLockOverlay(count, limit)
                }
                return
            }

            // Detect scroll gesture
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
                if (now - lastScrollTimestamp > scrollDebounceMs) {
                    lastScrollTimestamp = now
                    count++
                    prefs.edit().putInt(KEY_SCROLL_COUNT, count).apply()

                    val currentCount = count
                    mainHandler.post {
                        if (currentCount >= limit) {
                            hideFloatingOverlay()
                            showLockOverlay(currentCount, limit)
                        } else {
                            showFloatingOverlay(currentCount, limit)
                        }
                    }
                    return
                }
            }

            // Keep floating overlay shown and updated
            mainHandler.post {
                hideLockOverlay()
                showFloatingOverlay(count, limit)
            }
        } else if (!isTransientKeyboard(pkgName)) {
            val currentActive = getActivePackageName()
            if (currentActive == null || !isInstagramPackage(currentActive)) {
                isInstagramActive = false
                mainHandler.post {
                    hideFloatingOverlay()
                    hideLockOverlay()
                }
            }
        }
    }

    private fun getOverlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun showFloatingOverlay(count: Int, limit: Int) {
        val wm = windowManager ?: return

        if (floatingOverlayView == null) {
            val inflater = LayoutInflater.from(this)
            floatingOverlayView = inflater.inflate(R.layout.overlay_floating, null)

            val displayMetrics = resources.displayMetrics
            val initialX = (displayMetrics.widthPixels * 0.55).toInt()
            val initialY = (displayMetrics.heightPixels * 0.12).toInt()

            floatingParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                getOverlayWindowType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = initialX
                y = initialY
            }

            var startX = 0
            var startY = 0
            var touchX = 0f
            var touchY = 0f
            var isDragging = false

            floatingOverlayView?.setOnTouchListener { _, event ->
                val params = floatingParams ?: return@setOnTouchListener false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        startX = params.x
                        startY = params.y
                        touchX = event.rawX
                        touchY = event.rawY
                        isDragging = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - touchX).toInt()
                        val dy = (event.rawY - touchY).toInt()
                        if (abs(dx) > 12 || abs(dy) > 12) {
                            isDragging = true
                        }
                        params.x = startX + dx
                        params.y = startY + dy
                        try {
                            wm.updateViewLayout(floatingOverlayView, params)
                        } catch (e: Exception) {
                            // View might not be attached
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            }
                            if (intent != null) {
                                startActivity(intent)
                            }
                        }
                        true
                    }
                    else -> false
                }
            }
        }

        floatingOverlayView?.let { view ->
            val tvCount = view.findViewById<TextView>(R.id.tv_scroll_count)
            val tvLimit = view.findViewById<TextView>(R.id.tv_scroll_limit)
            val container = view.findViewById<View>(R.id.floating_pill_container)

            tvCount?.text = count.toString()
            tvLimit?.text = " / $limit"

            if (count >= limit - 1 && limit > 1) {
                container?.setBackgroundResource(R.drawable.bg_floating_pill_warning)
            } else {
                container?.setBackgroundResource(R.drawable.bg_floating_pill)
            }
        }

        if (!isFloatingOverlayVisible) {
            try {
                wm.addView(floatingOverlayView, floatingParams)
                isFloatingOverlayVisible = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else {
            try {
                wm.updateViewLayout(floatingOverlayView, floatingParams)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun hideFloatingOverlay() {
        if (isFloatingOverlayVisible && floatingOverlayView != null) {
            try {
                windowManager?.removeView(floatingOverlayView)
            } catch (e: Exception) {
                // View might not be attached
            }
            isFloatingOverlayVisible = false
        }
    }

    @SuppressLint("InflateParams")
    private fun showLockOverlay(count: Int, limit: Int) {
        val wm = windowManager ?: return

        if (lockOverlayView == null) {
            val inflater = LayoutInflater.from(this)
            lockOverlayView = inflater.inflate(R.layout.overlay_lock, null)

            lockParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                getOverlayWindowType(),
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
            }
        }

        lockOverlayView?.let { view ->
            val tvMessage = view.findViewById<TextView>(R.id.tv_lock_message)
            val tvStats = view.findViewById<TextView>(R.id.tv_lock_stats)

            tvMessage?.text = "You've reached your daily limit of $limit scrolls on Instagram. Step away and take a mindful break!"
            tvStats?.text = "Count: $count / $limit scrolls • Resets tomorrow at 12:00 AM"

            // Ensure Exit to Home button works reliably
            view.findViewById<Button>(R.id.btn_exit_home)?.setOnClickListener {
                isInstagramActive = false
                lockExitCooldownUntil = SystemClock.uptimeMillis() + 2500L
                hideLockOverlay()
                hideFloatingOverlay()
                try {
                    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                    }
                    startActivity(homeIntent)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                performGlobalAction(GLOBAL_ACTION_HOME)
            }

            // Ensure Adjust Limit in ScrollLock button opens app and dismisses overlay cleanly
            view.findViewById<Button>(R.id.btn_open_app)?.setOnClickListener {
                isInstagramActive = false
                lockExitCooldownUntil = SystemClock.uptimeMillis() + 2500L
                hideLockOverlay()
                hideFloatingOverlay()
                val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                if (intent != null) {
                    try {
                        startActivity(intent)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }

        if (!isLockOverlayVisible) {
            try {
                wm.addView(lockOverlayView, lockParams)
                isLockOverlayVisible = true
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun hideLockOverlay() {
        if (isLockOverlayVisible && lockOverlayView != null) {
            try {
                windowManager?.removeView(lockOverlayView)
            } catch (e: Exception) {
                // View might not be attached
            }
            isLockOverlayVisible = false
        }
    }

    fun syncState() {
        mainHandler.post {
            checkDailyReset(this)
            val prefs = getPrefs(this)
            val count = prefs.getInt(KEY_SCROLL_COUNT, 0)
            val limit = prefs.getInt(KEY_SCROLL_LIMIT, DEFAULT_LIMIT)

            val activePkg = getActivePackageName()
            val isIg = activePkg != null && isInstagramPackage(activePkg)

            if (isIg && SystemClock.uptimeMillis() >= lockExitCooldownUntil) {
                if (count >= limit) {
                    hideFloatingOverlay()
                    showLockOverlay(count, limit)
                } else {
                    hideLockOverlay()
                    showFloatingOverlay(count, limit)
                }
            } else {
                hideFloatingOverlay()
                hideLockOverlay()
            }
        }
    }

    override fun onInterrupt() {
        // Service interrupted
    }

    override fun onDestroy() {
        super.onDestroy()
        stopWatchdog()
        hideFloatingOverlay()
        hideLockOverlay()
        instance = null
    }
}
