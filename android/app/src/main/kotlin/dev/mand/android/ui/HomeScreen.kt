package dev.mand.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BatteryAlert
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.LaptopChromebook
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.PhonelinkOff
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.ChatLine
import dev.mand.android.net.LinkState

@Composable
fun HomeScreen(client: BridgeClient, phoneSecurityCode: String?, permissions: PermissionStatus, actions: HomeActions) {
    val state by client.state.collectAsStateWithLifecycle()
    val chat by client.chat.collectAsStateWithLifecycle()
    var confirmForget by rememberSaveable { mutableStateOf(false) }

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "M’AND",
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
                modifier = Modifier.semantics { heading() },
            )
            StatusCard(state, phoneSecurityCode, actions)
            when (state) {
                is LinkState.Connected -> TestMessageCard(chat, client::sendText)
                is LinkState.Searching -> TroubleshootingCard(client::setManualHost)
                else -> Unit
            }
            if (state !is LinkState.NotPaired) {
                if (!permissions.notifications) {
                    SetupCard(Icons.Outlined.Notifications, "Show connection status",
                        "Allow notifications so M’AND can show whether it’s connected.", "Allow", actions.requestNotifications)
                }
                if (!permissions.batteryUnrestricted) {
                    SetupCard(Icons.Outlined.BatteryAlert, "Stay connected in the background",
                        "Android may cut the connection to save battery. Allow M’AND to run unrestricted.",
                        "Allow", actions.requestBatteryExemption)
                }
            }
            ComingSoonCard()
            if (state is LinkState.Connected || state is LinkState.Searching || state is LinkState.Paused) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (state is LinkState.Paused) OutlinedButton(onClick = actions.resume) { Text("Reconnect") }
                    else OutlinedButton(onClick = actions.pause) { Text("Pause connection") }
                    TextButton(onClick = { confirmForget = true }) {
                        Text("Forget this Mac", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }

    if (confirmForget) {
        AlertDialog(
            onDismissRequest = { confirmForget = false },
            title = { Text("Forget this Mac?") },
            text = { Text("The Mac will be told, and this phone won’t connect again until you pair it.") },
            confirmButton = {
                TextButton(onClick = { confirmForget = false; client.forgetMac() }) {
                    Text("Forget", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmForget = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun StatusCard(state: LinkState, phoneSecurityCode: String?, actions: HomeActions) {
    val (icon, tint, title, subtitle) = describe(state)
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(56.dp).padding(0.dp),
                contentAlignment = Alignment.Center,
            ) {
                Surface(shape = CircleShape, color = tint.copy(alpha = 0.14f), modifier = Modifier.size(56.dp)) {}
                if (state is LinkState.Pairing || state is LinkState.Searching) {
                    CircularProgressIndicator(Modifier.size(56.dp), color = tint, strokeWidth = 2.dp)
                }
                Icon(icon, contentDescription = null, tint = tint)
            }
            Spacer(Modifier.width(16.dp))
            Column {
                Text(title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (state is LinkState.Pairing && state.step == LinkState.Pairing.Step.WAITING_FOR_APPROVAL) {
            Text(
                "Check that the Mac shows this security code:\n${phoneSecurityCode ?: "…"}",
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.padding(top = 12.dp),
            )
        }
        if (state is LinkState.NotPaired) {
            Steps()
            Button(onClick = actions.scanQr, modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Icon(Icons.Outlined.QrCodeScanner, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Pair with Mac")
            }
        }
    }
}

private data class StatusText(val icon: ImageVector, val tint: Color, val title: String, val subtitle: String)

@Composable
private fun describe(state: LinkState): StatusText {
    val primary = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    return when (state) {
        is LinkState.Connected -> StatusText(Icons.Outlined.Laptop, primary, "Connected",
            "${state.macName} · encrypted, local network")
        is LinkState.Searching -> StatusText(Icons.Outlined.Sync, muted, "Looking for ${state.macName}",
            state.lastError ?: "Make sure M’AND is open on the Mac and both are on the same Wi-Fi.")
        is LinkState.Pairing -> when (state.step) {
            LinkState.Pairing.Step.CONNECTING -> StatusText(Icons.Outlined.Sync, muted, "Connecting…",
                "Reaching ${state.macName.ifBlank { "your Mac" }} securely.")
            LinkState.Pairing.Step.WAITING_FOR_APPROVAL -> StatusText(Icons.Outlined.LaptopChromebook, primary,
                "Approve on your Mac", "Click “Allow” on ${state.macName} to finish pairing.")
        }
        is LinkState.Paused -> StatusText(Icons.Outlined.PhonelinkOff, muted, "Paused",
            (state.notice?.let { "$it\n" } ?: "") + "Paired with ${state.macName}. Tap Reconnect to connect again.")
        is LinkState.NotPaired -> StatusText(Icons.Outlined.PhonelinkOff, muted, "Not paired",
            state.notice ?: "Connect this phone to your Mac in about a minute.")
    }
}

@Composable
private fun Steps() {
    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf(
            "Open M’AND on your Mac and click “Pair a Phone”.",
            "Tap “Pair with Mac” below and scan the QR code.",
            "Click “Allow” on the Mac.",
        ).forEachIndexed { index, step ->
            Text("${index + 1}.  $step", style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun TestMessageCard(chat: List<ChatLine>, send: (String) -> Boolean) {
    var draft by rememberSaveable { mutableStateOf("") }
    Card(title = "Test message", subtitle = "Send a short note to check the connection.") {
        chat.takeLast(6).forEach { line ->
            Text(
                (if (line.fromMac) "Mac: " else "You: ") + line.text,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(vertical = 2.dp),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                placeholder = { Text("Type a message") },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { if (send(draft)) draft = "" }, enabled = draft.isNotBlank()) { Text("Send") }
        }
    }
}

@Composable
private fun TroubleshootingCard(setManualHost: (String) -> Unit) {
    var host by rememberSaveable { mutableStateOf("") }
    Card(title = "Can’t connect?") {
        listOf(
            "Open M’AND on the Mac.",
            "Use the same Wi-Fi on both (guest networks often block devices from seeing each other).",
            "If macOS asked about Local Network access for M’AND, choose Allow.",
        ).forEach { Tip(it) }
        Text(
            "Or enter the Mac’s address (shown on the Mac under “Can’t connect?”):",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(value = host, onValueChange = { host = it }, singleLine = true,
                placeholder = { Text("192.168.1.20") }, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = { setManualHost(host) }) { Text("Try") }
        }
    }
}

@Composable
private fun SetupCard(icon: ImageVector, title: String, body: String, button: String, onClick: () -> Unit) {
    Card {
        Row(verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall)
                Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onClick) { Text(button) }
        }
    }
}

@Composable
private fun ComingSoonCard() {
    Card(title = "Coming next", subtitle = "Not built yet — these will appear in later updates.") {
        listOf("Send files", "Clipboard sharing", "Phone notifications on the Mac", "Battery level on the Mac", "Screen mirroring")
            .forEach { Text("·  $it", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun Tip(text: String) {
    Row(Modifier.padding(vertical = 2.dp)) {
        Icon(Icons.Outlined.CheckCircle, contentDescription = null, modifier = Modifier.size(16.dp).padding(top = 2.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun Card(title: String? = null, subtitle: String? = null, content: @Composable () -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(18.dp)) {
            title?.let { Text(it, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)) }
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 8.dp))
            }
            content()
        }
    }
}
