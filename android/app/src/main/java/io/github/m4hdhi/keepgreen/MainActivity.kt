package io.github.m4hdhi.keepgreen

import android.content.Intent
import android.os.Bundle
import android.service.quicksettings.TileService
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.mutableStateOf
import io.github.m4hdhi.keepgreen.remote.PairingLink
import io.github.m4hdhi.keepgreen.ui.AppTab
import io.github.m4hdhi.keepgreen.ui.KeepGreenApp
import io.github.m4hdhi.keepgreen.ui.computers.ComputersViewModel
import io.github.m4hdhi.keepgreen.ui.theme.KeepGreenTheme

class MainActivity : ComponentActivity() {
    private val computers: ComputersViewModel by viewModels()
    private val requestedTab = mutableStateOf<AppTab?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // After a rotation the intent is the same one we already handled.
        if (savedInstanceState == null) handleIntent(intent)

        setContent {
            KeepGreenTheme {
                KeepGreenApp(
                    computers = computers,
                    requestedTab = requestedTab.value,
                    onTabRequestHandled = { requestedTab.value = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val data = intent.data
        when {
            intent.action == Intent.ACTION_VIEW && data != null && data.scheme == PairingLink.SCHEME -> {
                requestedTab.value = AppTab.Computers
                computers.onPairingLink(data.toString())
            }
            intent.getBooleanExtra(EXTRA_OPEN_PHONE, false) ||
                intent.action == TileService.ACTION_QS_TILE_PREFERENCES -> requestedTab.value = AppTab.Phone
        }
    }

    companion object {
        /** Opens the "This phone" tab, from the keep-awake notification or the Quick Settings tile. */
        const val EXTRA_OPEN_PHONE = "io.github.m4hdhi.keepgreen.extra.OPEN_PHONE"
    }
}
