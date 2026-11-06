package io.github.m4hdhi.keepgreen.data

import android.content.Context
import androidx.core.content.edit
import io.github.m4hdhi.keepgreen.remote.Desktop
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * The paired computers, kept as a JSON array in SharedPreferences.
 *
 * Each entry holds the computer's shared key, which is a secret: anyone with it can control that
 * computer's KeepGreen on the local network. The file is private to the app and excluded from
 * backups and device transfers (see res/xml/data_extraction_rules.xml). Moving to
 * EncryptedSharedPreferences or the Android Keystore is a future improvement.
 */
class DesktopStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
    private val state = MutableStateFlow(Desktop.listFromJson(prefs.getString(KEY_LIST, null)))

    val desktops: StateFlow<List<Desktop>> = state.asStateFlow()

    fun find(id: String): Desktop? = state.value.firstOrNull { it.id == id }

    fun findByAddress(host: String, port: Int): Desktop? =
        state.value.firstOrNull { it.host.equals(host, ignoreCase = true) && it.port == port }

    /** Adds [desktop], or replaces the entry with the same id. */
    fun upsert(desktop: Desktop) = change { list ->
        if (list.any { it.id == desktop.id }) list.map { if (it.id == desktop.id) desktop else it } else list + desktop
    }

    fun rename(id: String, name: String) = change { list ->
        list.map { if (it.id == id) it.copy(name = name.trim().ifEmpty { it.name }) else it }
    }

    fun remove(id: String) = change { list -> list.filterNot { it.id == id } }

    private fun change(transform: (List<Desktop>) -> List<Desktop>) {
        state.update(transform)
        prefs.edit { putString(KEY_LIST, Desktop.listToJson(state.value)) }
    }

    companion object {
        /** Also named in res/xml/data_extraction_rules.xml. */
        const val FILE_NAME = "desktops"
        private const val KEY_LIST = "list"
    }
}
