package io.github.m4hdhi.keepgreen.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.m4hdhi.keepgreen.ui.computers.ComputersTab
import io.github.m4hdhi.keepgreen.ui.computers.ComputersViewModel
import io.github.m4hdhi.keepgreen.ui.computers.PairLinkDialog
import io.github.m4hdhi.keepgreen.ui.phone.PhoneScreen

enum class AppTab(val label: String, val icon: ImageVector) {
    Computers("My computers", Icons.Rounded.Computer),
    Phone("This phone", Icons.Rounded.PhoneAndroid),
}

/**
 * The whole app: two tabs under a bottom bar. [requestedTab] lets the activity switch tabs for a
 * pairing link, the keep-awake notification or the Quick Settings tile.
 */
@Composable
fun KeepGreenApp(
    computers: ComputersViewModel,
    requestedTab: AppTab?,
    onTabRequestHandled: () -> Unit,
) {
    var tab by rememberSaveable { mutableStateOf(AppTab.Computers) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(requestedTab) {
        if (requestedTab != null) {
            tab = requestedTab
            onTabRequestHandled()
        }
    }

    val message by computers.message.collectAsStateWithLifecycle()
    LaunchedEffect(message) {
        val text = message ?: return@LaunchedEffect
        snackbar.showSnackbar(text)
        computers.messageShown()
    }

    Scaffold(
        // Each tab draws its own top bar, which handles the status bar inset.
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            NavigationBar {
                AppTab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = { Icon(item.icon, contentDescription = null) },
                        label = { Text(item.label) },
                    )
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (tab) {
                AppTab.Computers -> ComputersTab(computers)
                AppTab.Phone -> PhoneScreen()
            }
        }
    }

    val pendingLink by computers.pendingLink.collectAsStateWithLifecycle()
    val pairing by computers.pairing.collectAsStateWithLifecycle()
    pendingLink?.let { link ->
        PairLinkDialog(
            link = link,
            state = pairing,
            onPair = computers::pairFromLink,
            onDismiss = computers::dismissLink,
        )
    }
}
