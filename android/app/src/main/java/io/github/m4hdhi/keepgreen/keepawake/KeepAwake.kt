package io.github.m4hdhi.keepgreen.keepawake

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.quicksettings.TileService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** How the service is holding the screen on. */
enum class ScreenHold {
    /** An invisible 1×1 window with FLAG_KEEP_SCREEN_ON. Needs "Display over other apps". */
    Overlay,

    /** The older SCREEN_BRIGHT_WAKE_LOCK, used when the overlay isn't allowed. */
    WakeLock,
}

/** What "This phone" is doing right now. [endsAtMillis] and [minutes] are null for "Until I turn it off". */
data class KeepAwakeStatus(
    val isOn: Boolean = false,
    val minutes: Int? = null,
    val endsAtMillis: Long? = null,
    val hold: ScreenHold? = null,
)

/** A duration chip on the "This phone" screen. [minutes] is null for "Until I turn it off". */
data class KeepAwakeChoice(val label: String, val minutes: Int?)

/**
 * Entry point for keeping this phone's screen awake. [KeepAwakeService] does the work and publishes
 * its state here, so the screen and the Quick Settings tile always agree.
 */
object KeepAwake {
    val choices = listOf(
        KeepAwakeChoice("15 min", 15),
        KeepAwakeChoice("30 min", 30),
        KeepAwakeChoice("1 hour", 60),
        KeepAwakeChoice("2 hours", 120),
        KeepAwakeChoice("Until I turn it off", null),
    )

    private val state = MutableStateFlow(KeepAwakeStatus())
    val status: StateFlow<KeepAwakeStatus> = state.asStateFlow()

    /** Starts keeping the screen on, or restarts the timer if it's already on. */
    fun start(context: Context, minutes: Int?) {
        val intent = Intent(context, KeepAwakeService::class.java)
            .setAction(KeepAwakeService.ACTION_START)
            .putExtra(KeepAwakeService.EXTRA_MINUTES, minutes ?: 0)
        context.startForegroundService(intent)
    }

    fun stop(context: Context) {
        context.stopService(Intent(context, KeepAwakeService::class.java))
    }

    /** Asks a running service to switch to the overlay if it has just been allowed. Call from the foreground. */
    fun recheckHold(context: Context) {
        if (!status.value.isOn) return
        context.startService(Intent(context, KeepAwakeService::class.java).setAction(KeepAwakeService.ACTION_RECHECK))
    }

    internal fun publish(context: Context, status: KeepAwakeStatus) {
        state.value = status
        try {
            TileService.requestListeningState(context, ComponentName(context, KeepAwakeTileService::class.java))
        } catch (e: RuntimeException) {
            // The tile isn't essential; some launchers refuse this while it isn't added.
        }
    }
}
