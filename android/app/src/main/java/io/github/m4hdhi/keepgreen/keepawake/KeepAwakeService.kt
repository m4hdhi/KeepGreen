package io.github.m4hdhi.keepgreen.keepawake

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateFormat
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import io.github.m4hdhi.keepgreen.MainActivity
import io.github.m4hdhi.keepgreen.R
import java.util.Date

/**
 * Keeps the screen on for a while, with an ongoing notification that counts down and can stop it.
 *
 * The screen is held by an invisible 1×1 overlay window with FLAG_KEEP_SCREEN_ON when the user has
 * allowed "Display over other apps", and by a screen wake lock otherwise. Nothing is sent to other
 * apps: a chat app left open on screen simply stays open.
 */
class KeepAwakeService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var minutes: Int? = null
    private var endsAtMillis: Long? = null
    private var overlayView: View? = null
    private var overlayManager: WindowManager? = null
    private var wakeLock: PowerManager.WakeLock? = null

    /**
     * Checks the wall clock rather than trusting one long delay: Handler time stops while the phone
     * sleeps, which can happen if someone presses the power button mid-session.
     */
    private val tick = object : Runnable {
        override fun run() {
            val endsAt = endsAtMillis ?: return
            val left = endsAt - System.currentTimeMillis()
            if (left <= 0) {
                stopSelf()
            } else {
                handler.postDelayed(this, left.coerceAtMost(TICK_MILLIS))
            }
        }
    }

    private val hold: ScreenHold?
        get() = when {
            overlayView != null -> ScreenHold.Overlay
            wakeLock != null -> ScreenHold.WakeLock
            else -> null
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        when {
            intent != null && action == ACTION_START ->
                start(intent.getIntExtra(EXTRA_MINUTES, 0).takeIf { it > 0 })
            action == ACTION_RECHECK && running -> {
                holdScreen()
                publish()
            }
            // ACTION_STOP, a recheck with nothing running, or a restart we didn't ask for.
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        removeOverlay()
        releaseWakeLock()
        running = false
        KeepAwake.publish(this, KeepAwakeStatus())
        super.onDestroy()
    }

    private fun start(minutes: Int?) {
        this.minutes = minutes
        endsAtMillis = minutes?.let { System.currentTimeMillis() + it * 60_000L }
        if (!goForeground()) {
            stopSelf()
            return
        }
        running = true
        holdScreen()

        handler.removeCallbacks(tick)
        endsAtMillis?.let { endsAt ->
            handler.postDelayed(tick, (endsAt - System.currentTimeMillis()).coerceIn(0L, TICK_MILLIS))
        }
        publish()
    }

    private fun publish() {
        KeepAwake.publish(this, KeepAwakeStatus(isOn = true, minutes = minutes, endsAtMillis = endsAtMillis, hold = hold))
    }

    private fun goForeground(): Boolean = try {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        true
    } catch (e: RuntimeException) {
        false
    }

    // region Holding the screen on

    /** Prefers the overlay; falls back to the wake lock. Upgrades to the overlay once it's allowed. */
    private fun holdScreen() {
        if (overlayView != null) return
        if (addOverlay()) {
            releaseWakeLock()
        } else if (wakeLock == null) {
            acquireWakeLock()
        }
    }

    private fun addOverlay(): Boolean {
        if (!Settings.canDrawOverlays(this)) return false
        return try {
            val context = overlayContext()
            val manager = context.getSystemService(WindowManager::class.java) ?: return false
            val view = View(context)
            val params = WindowManager.LayoutParams(
                1,
                1,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                title = "KeepGreen"
            }
            manager.addView(view, params)
            overlayManager = manager
            overlayView = view
            true
        } catch (e: RuntimeException) {
            // BadTokenException or SecurityException: the permission was revoked or isn't honoured.
            false
        }
    }

    /** A window context for the overlay; services shouldn't use their own context for UI on Android 11+. */
    private fun overlayContext(): Context {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return this
        val display = getSystemService(DisplayManager::class.java)?.getDisplay(Display.DEFAULT_DISPLAY) ?: return this
        return createDisplayContext(display)
            .createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
    }

    private fun removeOverlay() {
        val view = overlayView ?: return
        try {
            overlayManager?.removeView(view)
        } catch (e: RuntimeException) {
            // Already gone.
        }
        overlayView = null
        overlayManager = null
    }

    // SCREEN_BRIGHT_WAKE_LOCK is deprecated in favour of FLAG_KEEP_SCREEN_ON, which needs a window.
    // Android still honours it, and it's the only way to hold the screen on without the overlay.
    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        val power = getSystemService(PowerManager::class.java) ?: return
        wakeLock = power.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ON_AFTER_RELEASE, WAKE_LOCK_TAG)
            .apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    // endregion

    // region Notification

    private fun buildNotification(): Notification {
        ensureChannel()
        val endsAt = endsAtMillis

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_OPEN_PHONE, true)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, KeepAwakeService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_glyph)
            .setColor(BRAND_GREEN)
            .setContentTitle("Keeping your screen awake")
            .setContentText(if (endsAt == null) "Until you turn it off" else "Until ${clock(endsAt)}")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, R.drawable.ic_stop), "Stop", stop).build())

        if (endsAt != null) {
            // The system draws the countdown, so the notification never needs updating.
            builder.setWhen(endsAt).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun ensureChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Keep screen awake", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shows while KeepGreen keeps this phone's screen on."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun clock(millis: Long): String = DateFormat.getTimeFormat(this).format(Date(millis))

    // endregion

    companion object {
        const val ACTION_START = "io.github.m4hdhi.keepgreen.action.KEEP_AWAKE_START"
        const val ACTION_STOP = "io.github.m4hdhi.keepgreen.action.KEEP_AWAKE_STOP"
        const val ACTION_RECHECK = "io.github.m4hdhi.keepgreen.action.KEEP_AWAKE_RECHECK"

        /** Minutes to stay awake; 0 means until turned off. */
        const val EXTRA_MINUTES = "minutes"

        private const val CHANNEL_ID = "keep_awake"
        private const val NOTIFICATION_ID = 1
        private const val TICK_MILLIS = 15_000L
        private const val WAKE_LOCK_TAG = "KeepGreen:screen"
        private val BRAND_GREEN = 0xFF22C55E.toInt()
    }
}
