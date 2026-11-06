package io.github.m4hdhi.keepgreen.ui.computers

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.m4hdhi.keepgreen.remote.HostAddress
import io.github.m4hdhi.keepgreen.remote.PairingLink

/**
 * Pair by typing what the desktop shows under Settings → Phone remote. A port typed after the
 * address ("192.168.1.20:47321") wins over the Port box.
 */
@Composable
fun AddComputerDialog(
    state: PairingState,
    onTest: (host: String, port: Int) -> Unit,
    onPair: (host: String, port: Int, code: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var address by rememberSaveable { mutableStateOf("") }
    var portText by rememberSaveable { mutableStateOf(PairingLink.DEFAULT_PORT.toString()) }
    var code by rememberSaveable { mutableStateOf("") }

    val parsed = HostAddress.parse(address)
    val typedPort = parsed?.port
    val port = typedPort ?: portText.toIntOrNull()?.takeIf { it in 1..65535 }
    val canReach = parsed != null && port != null && !state.working
    val canPair = canReach && PairingLink.isValidCode(code)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add computer") },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "On your computer, open KeepGreen → Settings → Phone remote. Type the address and code it shows.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = address,
                    onValueChange = { address = it.trim() },
                    label = { Text("Address") },
                    placeholder = { Text("192.168.1.20") },
                    singleLine = true,
                    isError = address.isNotEmpty() && parsed == null,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = typedPort?.toString() ?: portText,
                    onValueChange = { portText = it.filter(Char::isDigit).take(5) },
                    label = { Text("Port") },
                    singleLine = true,
                    enabled = typedPort == null,
                    isError = port == null,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.filter(Char::isDigit).take(6) },
                    label = { Text("Pairing code") },
                    placeholder = { Text("6 digits") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(
                        onClick = { if (parsed != null && port != null) onTest(parsed.host, port) },
                        enabled = canReach,
                    ) { Text("Test connection") }
                    if (state.working) {
                        Spacer(Modifier.width(8.dp))
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    }
                }
                PairingNote(state)
            }
        },
        confirmButton = {
            Button(
                onClick = { if (parsed != null && port != null) onPair(parsed.host, port, code) },
                enabled = canPair,
            ) { Text("Pair") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Confirms a `keepgreen://pair` link before trading its code for the key. */
@Composable
fun PairLinkDialog(link: PairingLink, state: PairingState, onPair: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Pair with ${link.name}?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "This phone will see how KeepGreen is doing on ${link.host}:${link.port} and be able to " +
                        "switch it on, off or boost it. Only pair computers you use.",
                )
                if (state.working) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(12.dp))
                        Text("Pairing…")
                    }
                }
                PairingNote(state)
            }
        },
        confirmButton = {
            Button(onClick = onPair, enabled = !state.working) { Text("Pair") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Not now") } },
    )
}

@Composable
private fun PairingNote(state: PairingState) {
    val note = state.note ?: return
    Text(
        note,
        style = MaterialTheme.typography.bodyMedium,
        color = if (state.noteIsError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
    )
}
