package io.github.m4hdhi.keepgreen.ui.computers

import android.text.format.DateFormat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CalendarToday
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FlashOn
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.m4hdhi.keepgreen.remote.Desktop
import io.github.m4hdhi.keepgreen.remote.DesktopStatus
import io.github.m4hdhi.keepgreen.remote.platformLabel
import io.github.m4hdhi.keepgreen.ui.components.SectionCard
import io.github.m4hdhi.keepgreen.ui.components.SectionHeader
import io.github.m4hdhi.keepgreen.ui.components.StatTile
import io.github.m4hdhi.keepgreen.ui.components.StatusOrb
import io.github.m4hdhi.keepgreen.ui.components.color
import io.github.m4hdhi.keepgreen.ui.theme.StatusColors
import io.github.m4hdhi.keepgreen.util.Humanize
import java.util.Date

private val BOOSTS = listOf("15 min" to 15, "30 min" to 30, "1 hour" to 60, "2 hours" to 120)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComputerDetailScreen(
    desktop: Desktop,
    connection: Connection?,
    busy: Boolean,
    viewModel: ComputersViewModel,
    onBack: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var renaming by rememberSaveable { mutableStateOf(false) }
    var removing by rememberSaveable { mutableStateOf(false) }

    val status = connection?.status
    val controlsEnabled = connection?.isOnline == true && !busy

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = { Text(desktop.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh(desktop.id) }) {
                        Icon(Icons.Rounded.Refresh, contentDescription = "Refresh")
                    }
                    Box {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Rounded.MoreVert, contentDescription = "More options")
                        }
                        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text("Rename") },
                                leadingIcon = { Icon(Icons.Rounded.Edit, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    renaming = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Remove") },
                                leadingIcon = { Icon(Icons.Rounded.Delete, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    removing = true
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            HeroCard(desktop, connection, onRetry = { viewModel.refresh(desktop.id) })
            if (status != null) {
                MasterSwitchCard(status, enabled = controlsEnabled, onChange = { viewModel.setEnabled(desktop.id, it) })
                BoostCard(
                    status = status,
                    enabled = controlsEnabled,
                    onBoost = { viewModel.boost(desktop.id, it) },
                    onUntilEndOfWorkday = { viewModel.boostUntilEndOfWorkday(desktop.id) },
                    onCancel = { viewModel.cancelBoost(desktop.id) },
                )
                TodayCard(status)
            }
            Text(
                listOf(
                    platformLabel(status?.platform ?: desktop.platform),
                    (status?.version ?: desktop.version).takeIf { it.isNotBlank() }?.let { "KeepGreen $it" },
                    desktop.address,
                ).filterNotNull().joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
            )
        }
    }

    if (renaming) {
        RenameDialog(
            current = desktop.name,
            onRename = {
                viewModel.rename(desktop.id, it)
                renaming = false
            },
            onDismiss = { renaming = false },
        )
    }
    if (removing) {
        AlertDialog(
            onDismissRequest = { removing = false },
            title = { Text("Remove ${desktop.name}?") },
            text = {
                Text(
                    "This phone stops showing and controlling it. You can pair it again any time. " +
                        "To sign out every phone, use Unpair all phones in KeepGreen on the computer.",
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        removing = false
                        viewModel.remove(desktop.id)
                        onBack()
                    },
                ) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { removing = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun HeroCard(desktop: Desktop, connection: Connection?, onRetry: () -> Unit) {
    val status = connection?.status
    val error = connection?.error
    SectionCard {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when {
                error != null -> {
                    StatusOrb(StatusColors.Disabled, Icons.Rounded.WifiOff, pulsing = false)
                    Headline("Can't reach ${desktop.name}")
                    Detail(error)
                    Spacer(Modifier.height(16.dp))
                    FilledTonalButton(onClick = onRetry) { Text("Try again") }
                }
                status != null -> {
                    StatusOrb(
                        color = status.tone.color(),
                        icon = if (status.isActive) Icons.Rounded.Check else Icons.Rounded.Pause,
                        pulsing = status.isActive,
                    )
                    Headline(status.headline.ifBlank { status.shortStatus })
                    if (status.detail.isNotBlank()) Detail(status.detail)
                    if (status.isBoosted) BoostPill(status)
                }
                else -> {
                    StatusOrb(StatusColors.Disabled, Icons.Rounded.MoreHoriz, pulsing = false)
                    Headline("Checking…")
                    Detail("Asking ${desktop.name} how it's doing.")
                }
            }
        }
    }
}

@Composable
private fun Headline(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.headlineSmall,
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(top = 16.dp),
    )
}

@Composable
private fun Detail(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun BoostPill(status: DesktopStatus) {
    val context = LocalContext.current
    val until = status.boostUntil?.let { DateFormat.getTimeFormat(context).format(Date(it.toInstant().toEpochMilli())) }
    Surface(
        shape = RoundedCornerShape(50),
        color = MaterialTheme.colorScheme.primaryContainer,
        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        modifier = Modifier.padding(top = 12.dp),
    ) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.FlashOn, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(if (until != null) "Boost on until $until" else "Boost on", style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun MasterSwitchCard(status: DesktopStatus, enabled: Boolean, onChange: (Boolean) -> Unit) {
    SectionCard {
        Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("KeepGreen", style = MaterialTheme.typography.titleMedium)
                Text(
                    if (status.isEnabled) "On. Keeps this computer awake and your status available." else "Off. Turn it on to stay green.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(12.dp))
            Switch(checked = status.isEnabled, onCheckedChange = onChange, enabled = enabled)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BoostCard(
    status: DesktopStatus,
    enabled: Boolean,
    onBoost: (Int) -> Unit,
    onUntilEndOfWorkday: () -> Unit,
    onCancel: () -> Unit,
) {
    SectionCard {
        Column(Modifier.padding(20.dp)) {
            SectionHeader(Icons.Rounded.FlashOn, "Quick boost")
            Text(
                "Stay green for a while, even outside your schedule or with the switch off.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                BOOSTS.forEach { (label, minutes) ->
                    OutlinedButton(onClick = { onBoost(minutes) }, enabled = enabled) { Text(label) }
                }
                OutlinedButton(onClick = onUntilEndOfWorkday, enabled = enabled) { Text("Until the end of my workday") }
                if (status.isBoosted) {
                    Button(
                        onClick = onCancel,
                        enabled = enabled,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error,
                            contentColor = MaterialTheme.colorScheme.onError,
                        ),
                    ) { Text("Cancel boost") }
                }
            }
        }
    }
}

@Composable
private fun TodayCard(status: DesktopStatus) {
    SectionCard {
        Column(Modifier.padding(20.dp)) {
            SectionHeader(Icons.Rounded.CalendarToday, "Today")
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                StatTile("Idle now", Humanize.duration(status.idleSeconds), "On the computer", Modifier.weight(1f))
                StatTile("Nudges today", Humanize.count(status.nudgesToday), "Only when idle", Modifier.weight(1f))
                StatTile("Green today", Humanize.duration(status.greenSecondsToday), "Time it was active", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun RenameDialog(current: String, onRename: (String) -> Unit, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(current) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rename computer") },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it.take(60) },
                label = { Text("Name") },
                singleLine = true,
            )
        },
        confirmButton = {
            TextButton(onClick = { onRename(name.trim()) }, enabled = name.isNotBlank()) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
