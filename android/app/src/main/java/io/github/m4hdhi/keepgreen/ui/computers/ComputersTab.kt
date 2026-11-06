package io.github.m4hdhi.keepgreen.ui.computers

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay

private const val REFRESH_INTERVAL_MILLIS = 5_000L

/** "My computers": the list, or one computer's detail, plus the Add computer dialog. */
@Composable
fun ComputersTab(viewModel: ComputersViewModel) {
    val desktops by viewModel.desktops.collectAsStateWithLifecycle()
    val connections by viewModel.connections.collectAsStateWithLifecycle()
    val refreshing by viewModel.refreshing.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    val pairing by viewModel.pairing.collectAsStateWithLifecycle()

    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var showAdd by rememberSaveable { mutableStateOf(false) }

    AutoRefresh(viewModel)

    // A successful pairing (typed or from a link) opens the new computer.
    LaunchedEffect(pairing.pairedId) {
        val id = pairing.pairedId ?: return@LaunchedEffect
        showAdd = false
        openId = id
        viewModel.resetPairing()
    }

    val open = desktops.firstOrNull { it.id == openId }
    if (open != null) {
        BackHandler { openId = null }
        ComputerDetailScreen(
            desktop = open,
            connection = connections[open.id],
            busy = open.id in busy,
            viewModel = viewModel,
            onBack = { openId = null },
        )
    } else {
        ComputerListScreen(
            desktops = desktops,
            connections = connections,
            refreshing = refreshing,
            onRefresh = viewModel::refreshAll,
            onOpen = { openId = it },
            onAdd = {
                viewModel.resetPairing()
                showAdd = true
            },
        )
    }

    if (showAdd) {
        AddComputerDialog(
            state = pairing,
            onTest = viewModel::testConnection,
            onPair = { host, port, code -> viewModel.pair(host, port, code) },
            onDismiss = {
                showAdd = false
                viewModel.resetPairing()
            },
        )
    }
}

/** Polls every computer every few seconds, but only while the app is on screen. */
@Composable
private fun AutoRefresh(viewModel: ComputersViewModel) {
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner, viewModel) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                viewModel.refreshAllNow()
                delay(REFRESH_INTERVAL_MILLIS)
            }
        }
    }
}
