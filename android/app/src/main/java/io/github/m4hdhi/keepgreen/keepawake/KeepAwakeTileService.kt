package io.github.m4hdhi.keepgreen.keepawake

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.text.format.DateFormat
import io.github.m4hdhi.keepgreen.MainActivity
import io.github.m4hdhi.keepgreen.R
import java.util.Date
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Quick Settings tile: one tap keeps the screen awake until tapped again. */
class KeepAwakeTileService : TileService() {
    private val scope = MainScope()
    private var listening: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        listening?.cancel()
        listening = scope.launch { KeepAwake.status.collect { render(it) } }
    }

    override fun onStopListening() {
        listening?.cancel()
        listening = null
        super.onStopListening()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onClick() {
        super.onClick()
        if (KeepAwake.status.value.isOn) {
            KeepAwake.stop(this)
            return
        }
        try {
            KeepAwake.start(this, minutes = null)
        } catch (e: IllegalStateException) {
            // Android can refuse to start a foreground service from here. The app itself always can.
            openApp()
        }
    }

    private fun render(status: KeepAwakeStatus) {
        val tile = qsTile ?: return
        tile.state = if (status.isOn) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.tile_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val endsAt = status.endsAtMillis
            tile.subtitle = when {
                !status.isOn -> "Off"
                endsAt == null -> "Screen on"
                else -> "Until ${DateFormat.getTimeFormat(this).format(Date(endsAt))}"
            }
        }
        tile.contentDescription = if (status.isOn) "KeepGreen, keeping the screen awake" else "KeepGreen, screen awake is off"
        tile.updateTile()
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_OPEN_PHONE, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
