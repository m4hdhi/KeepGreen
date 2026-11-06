package io.github.m4hdhi.keepgreen.ui.phone

import android.Manifest
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Widgets
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.m4hdhi.keepgreen.R
import io.github.m4hdhi.keepgreen.keepawake.KeepAwake
import io.github.m4hdhi.keepgreen.keepawake.KeepAwakeStatus
import io.github.m4hdhi.keepgreen.keepawake.KeepAwakeTileService
import io.github.m4hdhi.keepgreen.keepawake.ScreenHold
import io.github.m4hdhi.keepgreen.ui.components.SectionCard
import io.github.m4hdhi.keepgreen.ui.components.SectionHeader
import io.github.m4hdhi.keepgreen.ui.components.StatusOrb
import io.github.m4hdhi.keepgreen.ui.theme.StatusColors
import io.github.m4hdhi.keepgreen.util.Humanize
import java.util.Date
import kotlinx.coroutines.delay

/** Index into [KeepAwake.choices] picked when nothing is running: "1 hour". */
private const val DEFAULT_CHOICE = 2

/** "This phone": keep this phone's own screen awake, so a chat app left open stays Available. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhoneScreen() {
    val context = LocalContext.current
    val status by KeepAwake.status.collectAsStateWithLifecycle()
    var choice by rememberSaveable { mutableIntStateOf(DEFAULT_CHOICE) }
    var canOverlay by remember { mutableStateOf(Settings.canDrawOverlays(context)) }

    // Coming back from the "Display over other apps" screen: pick up the new permission.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        canOverlay = Settings.canDrawOverlays(context)
        if (canOverlay && status.hold == ScreenHold.WakeLock) KeepAwake.recheckHold(context)
    }

    // Started after the notification permission prompt, whatever the answer: the screen still stays
    // on without it, the notification just isn't shown.
    val notificationPrompt = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        KeepAwake.start(context, KeepAwake.choices[choice].minutes)
    }

    fun turnOn() {
        val needsPrompt = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        if (needsPrompt) {
            notificationPrompt.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            KeepAwake.start(context, KeepAwake.choices[choice].minutes)
        }
    }

    // While running, the chips show the running duration; tapping one restarts the timer.
    val selected = if (status.isOn) KeepAwake.choices.indexOfFirst { it.minutes == status.minutes } else choice

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = { TopAppBar(title = { Text("This phone") }) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            HeroCard(status)

            SectionCard {
                Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Keep screen awake", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Stops this phone's screen from turning off by itself.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Switch(
                        checked = status.isOn,
                        onCheckedChange = { on -> if (on) turnOn() else KeepAwake.stop(context) },
                    )
                }
            }

            DurationCard(
                selected = selected,
                onSelect = { index ->
                    choice = index
                    if (status.isOn) KeepAwake.start(context, KeepAwake.choices[index].minutes)
                },
            )

            if (!canOverlay) OverlayCard(onAllow = { openOverlaySettings(context) })

            ExplanationCard()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) TileCard(onAdd = { requestTile(context) })
        }
    }
}

@Composable
private fun HeroCard(status: KeepAwakeStatus) {
    val context = LocalContext.current
    // Ticks once a second while a timer runs, for the countdown.
    val now by produceState(System.currentTimeMillis(), status.endsAtMillis) {
        while (status.endsAtMillis != null) {
            value = System.currentTimeMillis()
            delay(1_000)
        }
    }
    val endsAt = status.endsAtMillis
    val (headline, detail) = when {
        !status.isOn -> "Your screen can turn off" to
            "Turn this on, then open Teams. It shows you Available while it's open on screen."
        endsAt == null -> "Your screen stays on" to "Until you turn it off."
        else -> "Your screen stays on" to
            "Turns off in ${Humanize.duration((endsAt - now) / 1000)}, at ${DateFormat.getTimeFormat(context).format(Date(endsAt))}."
    }

    SectionCard {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            StatusOrb(
                color = if (status.isOn) StatusColors.Active else StatusColors.Disabled,
                icon = if (status.isOn) Icons.Rounded.LightMode else Icons.Rounded.DarkMode,
                pulsing = status.isOn,
            )
            Text(
                headline,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 16.dp),
            )
            Text(
                detail,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun DurationCard(selected: Int, onSelect: (Int) -> Unit) {
    SectionCard {
        Column(Modifier.padding(20.dp)) {
            SectionHeader(Icons.Rounded.Timer, "For how long")
            FlowRow(
                modifier = Modifier.padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                KeepAwake.choices.forEachIndexed { index, option ->
                    FilterChip(
                        selected = index == selected,
                        onClick = { onSelect(index) },
                        label = { Text(option.label) },
                    )
                }
            }
        }
    }
}

@Composable
private fun OverlayCard(onAllow: () -> Unit) {
    SectionCard {
        Column(Modifier.padding(20.dp)) {
            SectionHeader(Icons.Rounded.Layers, "Make it work on every phone")
            Text(
                "Allow KeepGreen to display over other apps. It only adds an invisible 1-pixel window that " +
                    "asks Android to keep the screen on. You won't see it, and it can't read or touch anything. " +
                    "Without it, KeepGreen uses an older method that some phones ignore.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp, bottom = 12.dp),
            )
            FilledTonalButton(onClick = onAllow) { Text("Open settings") }
        }
    }
}

@Composable
private fun ExplanationCard() {
    SectionCard {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionHeader(Icons.Rounded.Info, "How this helps")
            Body(
                "Teams on a phone shows you Available only while it's open on screen. When the screen " +
                    "turns off, you go Away after a few minutes.",
            )
            Body("Turn this on, open Teams, and leave your phone on its charger. KeepGreen keeps the screen on, nothing more.")
            Body(
                "Android doesn't let apps act on other apps, so this phone can't stay green in the background. " +
                    "To keep your computer green, use My computers.",
            )
        }
    }
}

@Composable
private fun TileCard(onAdd: () -> Unit) {
    SectionCard {
        Column(Modifier.padding(20.dp)) {
            SectionHeader(Icons.Rounded.Widgets, "One tap from anywhere")
            Body(
                "Add the KeepGreen tile to Quick Settings to keep the screen awake until you tap it again.",
                Modifier.padding(top = 8.dp, bottom = 4.dp),
            )
            TextButton(onClick = onAdd) { Text("Add tile") }
        }
    }
}

@Composable
private fun Body(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

private fun openOverlaySettings(context: Context) {
    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
    try {
        context.startActivity(intent)
    } catch (e: RuntimeException) {
        // Some phones hide the per-app page; fall back to the list.
        context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
    }
}

/** Android 13+ can offer to add the tile right from the app. */
private fun requestTile(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val statusBar = context.getSystemService(StatusBarManager::class.java) ?: return
    statusBar.requestAddTileService(
        ComponentName(context, KeepAwakeTileService::class.java),
        context.getString(R.string.tile_label),
        Icon.createWithResource(context, R.drawable.ic_glyph),
        context.mainExecutor,
    ) { }
}
