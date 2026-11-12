package dev.mand.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BatteryAlert
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material.icons.outlined.LaptopChromebook
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.PhonelinkOff
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.WifiFind
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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.ChatLine
import dev.mand.android.net.LinkState

data class PermissionStatus(val notifications: Boolean, val batteryUnrestricted: Boolean)

class HomeActions(
    val scanQr: () -> Unit,
    val requestNotifications: () -> Unit,
    val requestBatteryExemption: () -> Unit,
    val requestLocalNetwork: () -> Unit,
    val resume: () -> Unit,
    val pause: () -> Unit,
    val retry: () -> Unit,
)

@Composable
fun HomeScreen(
    client: BridgeClient,
    phoneSecurityCode: String?,
    permissions: PermissionStatus,
    actions: HomeActions,
    features: @Composable (connected: Boolean) -> Unit = {},
) {
    val state by client.state.collectAsStateWithLifecycle()
    val chat by client.chat.collectAsStateWithLifecycle()
    var confirmForget by rememberSaveable { mutableStateOf(false) }

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(Space.L),
            verticalArrangement = Arrangement.spacedBy(Space.L),
        ) {
            Column {
                Text(
                    "M’AND",
                    style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.semantics { heading() },
                )
                Text("Your phone. Your Mac. One ecosystem.", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            StatusHero(state, phoneSecurityCode, actions)
            when (state) {
                is LinkState.Connected -> MessagesCard(chat, client::sendText)
                is LinkState.Searching -> TroubleshootingCard(client::setManualHost)
                else -> Unit
            }
            val paired = state !is LinkState.NotPaired && state !is LinkState.Pairing
            if (state !is LinkState.NotPaired) {
                if (!permissions.notifications) {
                    SetupCard(Icons.Outlined.Notifications, "Show connection status",
                        "Allow notifications so M’AND can show whether it’s connected.", "Allow notifications", actions.requestNotifications)
                }
                if (!permissions.batteryUnrestricted) {
                    SetupCard(Icons.Outlined.BatteryAlert, "Stay connected in the background",
                        "Android may cut the connection to save battery. Allow M’AND to run unrestricted.",
                        "Keep M’AND connected", actions.requestBatteryExemption)
                }
            }
            if (paired) {
                features(state is LinkState.Connected)
                ButtonRow {
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

/** The glanceable status: what's connected, and the one action that fixes the current problem. */
@Composable
internal fun StatusHero(state: LinkState, phoneSecurityCode: String?, actions: HomeActions) {
    val look = describe(state)
    MandCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier.size(64.dp).background(look.tint.copy(alpha = 0.12f), CircleShape)
                        .border(2.dp, if (state is LinkState.Connected) look.tint else Color.Transparent, CircleShape),
                )
                if (look.busy) CircularProgressIndicator(Modifier.size(64.dp), color = look.tint, strokeWidth = 2.dp)
                Icon(look.icon, contentDescription = null, tint = look.tint)
            }
            Spacer(Modifier.width(Space.L))
            // Read as one sentence, and announced by TalkBack whenever the status changes.
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }) {
                Text(
                    look.chip,
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                    color = look.tint,
                    modifier = Modifier.semantics { contentDescription = "Status: ${look.chip}" },
                )
                Text(look.title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold))
                Text(look.subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (state is LinkState.Pairing && state.step == LinkState.Pairing.Step.WAITING_FOR_APPROVAL) {
            Text("Check that your Mac shows the same code. If it doesn’t, cancel on the Mac.",
                style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = Space.M))
            Text(
                phoneSecurityCode ?: "…",
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace),
                // Spoken character by character so it can be compared.
                modifier = Modifier.semantics { contentDescription = (phoneSecurityCode ?: "").toList().joinToString(" ") },
            )
        }
        when (state) {
            is LinkState.NotPaired -> {
                Steps()
                Button(onClick = actions.scanQr, modifier = Modifier.fillMaxWidth().padding(top = Space.M)) {
                    Icon(Icons.Outlined.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.width(Space.S))
                    Text("Pair with Mac")
                }
            }
            is LinkState.NeedsPermission -> Button(
                onClick = actions.requestLocalNetwork,
                modifier = Modifier.fillMaxWidth().padding(top = Space.M),
            ) { Text("Allow finding my Mac") }
            is LinkState.Searching -> if (state.resting) {
                OutlinedButton(onClick = actions.retry, modifier = Modifier.padding(top = Space.M)) { Text("Try again now") }
            }
            else -> Unit
        }
    }
}

private data class StatusLook(
    val icon: ImageVector,
    val tint: Color,
    val chip: String,
    val title: String,
    val subtitle: String,
    val busy: Boolean = false,
)

@Composable
private fun describe(state: LinkState): StatusLook {
    val accent = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val warn = MaterialTheme.colorScheme.error
    return when (state) {
        is LinkState.Connected -> StatusLook(Icons.Outlined.Laptop, accent, "Connected", state.macName,
            "Connected safely over your Wi-Fi")
        is LinkState.Searching -> if (state.resting) {
            StatusLook(Icons.Outlined.Sync, muted, "Not connected", "Can’t reach ${state.macName}",
                "Open M’AND on your Mac and join the same Wi-Fi. M’AND keeps trying automatically.")
        } else {
            StatusLook(Icons.Outlined.Sync, muted, "Looking", "Looking for ${state.macName}",
                state.lastError ?: "Make sure M’AND is open on the Mac and both are on the same Wi-Fi.", busy = true)
        }
        is LinkState.Offline -> StatusLook(Icons.Outlined.CloudOff, muted, "Offline", "No network",
            "M’AND will reconnect to ${state.macName} as soon as you’re back on Wi-Fi.")
        is LinkState.NeedsPermission -> StatusLook(Icons.Outlined.WifiFind, warn, "Permission needed",
            "One permission needed", "Android will ask once. Tap Allow so your phone can find ${state.macName} on Wi-Fi.")
        is LinkState.Pairing -> when (state.step) {
            LinkState.Pairing.Step.CONNECTING -> StatusLook(Icons.Outlined.Sync, muted, "Pairing", "Connecting…",
                "Reaching ${state.macName.ifBlank { "your Mac" }} securely.", busy = true)
            LinkState.Pairing.Step.WAITING_FOR_APPROVAL -> StatusLook(Icons.Outlined.LaptopChromebook, accent,
                "Pairing", "Approve on your Mac", "Click “Allow” on ${state.macName} to finish pairing.", busy = true)
        }
        is LinkState.Paused -> StatusLook(Icons.Outlined.PhonelinkOff, muted, "Paused", state.macName,
            (state.notice?.let { "$it\n" } ?: "") + "Tap Reconnect to connect again.")
        is LinkState.NotPaired -> StatusLook(Icons.Outlined.PhonelinkOff, muted, "Not paired", "Pair with your Mac",
            state.notice ?: "Connect this phone to your Mac in about a minute.")
    }
}

@Composable
private fun Steps() {
    Column(Modifier.padding(top = Space.M), verticalArrangement = Arrangement.spacedBy(Space.XS)) {
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
private fun MessagesCard(chat: List<ChatLine>, send: (String) -> Boolean) {
    var draft by rememberSaveable { mutableStateOf("") }
    MandCard(title = "Messages", subtitle = "Send a quick note to your Mac.") {
        if (chat.isEmpty()) Hint("No messages yet. Anything you send appears on your Mac.")
        chat.takeLast(6).forEach { line ->
            Text((if (line.fromMac) "Mac: " else "You: ") + line.text, style = MaterialTheme.typography.bodyMedium)
        }
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            label = { Text("Message") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (draft.isNotBlank() && send(draft)) draft = "" }),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { if (send(draft)) draft = "" }, enabled = draft.isNotBlank()) { Text("Send") }
    }
}

@Composable
private fun TroubleshootingCard(setManualHost: (String) -> Unit) {
    var host by rememberSaveable { mutableStateOf("") }
    MandCard(title = "Can’t connect?") {
        listOf(
            "Open M’AND on the Mac.",
            "Use the same Wi-Fi on both (guest networks often block devices from seeing each other).",
            "If macOS asked about Local Network access for M’AND, choose Allow.",
        ).forEachIndexed { index, tip -> Tip("${index + 1}. $tip") }
        Hint("Still stuck? Type the Mac’s address. The Mac shows it under “Can’t connect?”.")
        OutlinedTextField(
            value = host, onValueChange = { host = it }, singleLine = true,
            label = { Text("Mac’s address") }, placeholder = { Text("192.168.1.20") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { setManualHost(host) }),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(onClick = { setManualHost(host) }, enabled = host.isNotBlank()) { Text("Connect") }
    }
}

@Composable
private fun SetupCard(icon: ImageVector, title: String, body: String, button: String, onClick: () -> Unit) {
    MandCard {
        Row(verticalAlignment = Alignment.Top) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(Space.M))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        OutlinedButton(onClick = onClick) { Text(button) }
    }
}

@Composable
private fun Tip(text: String) {
    Row(Modifier.padding(vertical = 2.dp)) {
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}
