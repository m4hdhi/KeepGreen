package io.github.m4hdhi.keepgreen.ui.computers

import android.app.Application
import android.os.Build
import android.provider.Settings
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.m4hdhi.keepgreen.data.DesktopStore
import io.github.m4hdhi.keepgreen.remote.Desktop
import io.github.m4hdhi.keepgreen.remote.DesktopStatus
import io.github.m4hdhi.keepgreen.remote.PairingLink
import io.github.m4hdhi.keepgreen.remote.RemoteClient
import io.github.m4hdhi.keepgreen.remote.RemoteException
import io.github.m4hdhi.keepgreen.remote.platformLabel
import java.util.UUID
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The last thing we heard from a computer. Both null means we're still asking. */
data class Connection(val status: DesktopStatus? = null, val error: String? = null) {
    val isOnline: Boolean get() = status != null && error == null
}

/** Progress of the Add computer dialog or a pairing link. */
data class PairingState(
    val working: Boolean = false,
    val note: String? = null,
    val noteIsError: Boolean = false,
    val pairedId: String? = null,
)

/** Everything on the "My computers" tab: the paired list, their live status, and pairing. */
class ComputersViewModel(application: Application) : AndroidViewModel(application) {
    private val store = DesktopStore(application)
    private val client = RemoteClient()

    val desktops: StateFlow<List<Desktop>> = store.desktops

    private val _connections = MutableStateFlow<Map<String, Connection>>(emptyMap())
    val connections: StateFlow<Map<String, Connection>> = _connections.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    /** Ids of computers with a command in flight, so their controls can wait. */
    private val _busy = MutableStateFlow<Set<String>>(emptySet())
    val busy: StateFlow<Set<String>> = _busy.asStateFlow()

    /** One-off sentence for a snackbar. */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    /** A `keepgreen://pair` link waiting for the user to confirm. */
    private val _pendingLink = MutableStateFlow<PairingLink?>(null)
    val pendingLink: StateFlow<PairingLink?> = _pendingLink.asStateFlow()

    private val _pairing = MutableStateFlow(PairingState())
    val pairing: StateFlow<PairingState> = _pairing.asStateFlow()

    // region Status

    /** Pull-to-refresh and the refresh button. */
    fun refreshAll() {
        if (_refreshing.value) return
        viewModelScope.launch {
            _refreshing.value = true
            try {
                refreshAllNow()
            } finally {
                _refreshing.value = false
            }
        }
    }

    /** Asks every computer for its status at once and returns when all have answered or failed. */
    suspend fun refreshAllNow() = coroutineScope {
        desktops.value.forEach { desktop -> launch { refresh(desktop) } }
    }

    fun refresh(id: String) {
        val desktop = store.find(id) ?: return
        viewModelScope.launch { refresh(desktop) }
    }

    private suspend fun refresh(desktop: Desktop) {
        val connection = try {
            Connection(status = client.status(desktop))
        } catch (e: RemoteException) {
            Connection(status = _connections.value[desktop.id]?.status, error = e.message)
        }
        _connections.update { it + (desktop.id to connection) }
    }

    // endregion

    // region Commands

    fun setEnabled(id: String, enabled: Boolean) = command(id) { client.setEnabled(it, enabled) }

    fun boost(id: String, minutes: Int) = command(id) { client.boost(it, minutes) }

    fun boostUntilEndOfWorkday(id: String) = command(id) { client.boostUntilEndOfWorkday(it) }

    fun cancelBoost(id: String) = command(id) { client.cancelBoost(it) }

    private fun command(id: String, call: suspend (Desktop) -> DesktopStatus) {
        val desktop = store.find(id) ?: return
        if (id in _busy.value) return
        viewModelScope.launch {
            _busy.update { it + id }
            try {
                val status = call(desktop)
                _connections.update { it + (id to Connection(status = status)) }
            } catch (e: RemoteException) {
                _message.value = e.message
            } finally {
                _busy.update { it - id }
            }
        }
    }

    fun rename(id: String, name: String) {
        if (name.isNotBlank()) store.rename(id, name)
    }

    fun remove(id: String) {
        val name = store.find(id)?.name ?: return
        store.remove(id)
        _connections.update { it - id }
        _message.value = "Removed $name."
    }

    fun messageShown() {
        _message.value = null
    }

    // endregion

    // region Pairing

    fun resetPairing() {
        _pairing.value = PairingState()
    }

    /** "Test connection" in the Add computer dialog: an unsigned ping. */
    fun testConnection(host: String, port: Int) {
        viewModelScope.launch {
            _pairing.value = PairingState(working = true)
            _pairing.value = try {
                val info = client.ping(host, port)
                PairingState(note = "Found ${info.name} (${platformLabel(info.platform)}, KeepGreen ${info.version}). Now type the code it shows.")
            } catch (e: RemoteException) {
                PairingState(note = e.message, noteIsError = true)
            }
        }
    }

    /**
     * Trades the code for the key and saves the computer. Pairing the same address again replaces
     * the old key but keeps the name the user gave it.
     */
    fun pair(host: String, port: Int, code: String, suggestedName: String? = null) {
        if (_pairing.value.working) return
        viewModelScope.launch {
            _pairing.value = PairingState(working = true)
            try {
                val result = client.pair(host, port, code, deviceName())
                val existing = store.findByAddress(host, port)
                val desktop = Desktop(
                    id = existing?.id ?: UUID.randomUUID().toString(),
                    host = host,
                    port = port,
                    key = result.key,
                    name = existing?.name ?: suggestedName?.takeIf { it.isNotBlank() } ?: result.name.ifBlank { host },
                    platform = result.platform,
                    version = result.version,
                )
                store.upsert(desktop)
                _pendingLink.value = null
                _pairing.value = PairingState(pairedId = desktop.id)
                _message.value = "Paired with ${desktop.name}."
                refresh(desktop)
            } catch (e: RemoteException) {
                _pairing.value = PairingState(note = e.message, noteIsError = true)
            }
        }
    }

    /** Called with the data of a `keepgreen://pair` intent. */
    fun onPairingLink(uri: String) {
        val link = PairingLink.parse(uri)
        if (link == null) {
            _message.value = "That pairing link doesn't look right. Tap Add computer and type the address and code instead."
            return
        }
        resetPairing()
        _pendingLink.value = link
    }

    fun pairFromLink() {
        val link = _pendingLink.value ?: return
        pair(link.host, link.port, link.code, link.name)
    }

    fun dismissLink() {
        _pendingLink.value = null
        resetPairing()
    }

    /** How the desktop lists this phone: the name set in Settings → About phone, else the model. */
    private fun deviceName(): String {
        val app = getApplication<Application>()
        val named = Settings.Global.getString(app.contentResolver, Settings.Global.DEVICE_NAME)
        if (!named.isNullOrBlank()) return named
        val model = Build.MODEL.orEmpty()
        val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.uppercase() }
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }

    // endregion
}
