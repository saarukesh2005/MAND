package dev.mand.android.ui

import android.content.Intent
import android.content.pm.PackageManager
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.mand.android.MandApp
import dev.mand.android.files.TransferItem
import dev.mand.android.files.TransferState
import dev.mand.core.Feature

/** Files, clipboard and notification sections of the home screen. Shown once a Mac is paired. */
@Composable
fun FeatureCards(app: MandApp, connected: Boolean, notificationAccess: Boolean, actions: FeatureActions, tapEnabled: Boolean = false) {
    TapCard(app, connected, tapEnabled, actions)
    FilesCard(app, connected, actions)
    ClipboardCard(app, connected)
    NotificationsCard(app, notificationAccess, actions)
    CallsCard(app, actions)
    Text(
        "Battery level is shared with your Mac automatically while connected.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

class FeatureActions(
    val pickFiles: () -> Unit,
    val openNotificationAccess: () -> Unit,
    /** Asks for the phone permissions Calls on Mac needs; the callback says whether they were granted. */
    val requestCallPermissions: (onResult: (Boolean) -> Unit) -> Unit,
    val openAccessibility: () -> Unit = {},
    /** Asks for SMS permission (codes to the Mac); the callback says whether it was granted. */
    val requestSms: (onResult: (Boolean) -> Unit) -> Unit = {},
)

@Composable
private fun TapCard(app: MandApp, connected: Boolean, tapEnabled: Boolean, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    var choosing by rememberSaveable { mutableStateOf(false) }
    var smsDenied by rememberSaveable { mutableStateOf(false) }
    SectionCard(
        title = "Tap to Send",
        subtitle = "Touch the top of your phone to your MacBook’s notch to send what’s on screen. Your Mac checks the " +
            "screen’s light, so it only works when the phone is really on the notch.",
    ) {
        if (tapEnabled) {
            Text(
                if (connected && app.client.macSupports(dev.mand.core.Feature.TAP)) "Ready. Turn on Tap to Send on your Mac too (Settings)."
                else "On. Waiting for your Mac to connect.",
                style = MaterialTheme.typography.bodyMedium,
            )
        } else {
            Text(
                "Android needs you to switch on “M’AND Tap to Send” in Accessibility settings. If it’s greyed out, " +
                    "open App info → ⋮ → “Allow restricted settings” first.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        OutlinedButton(onClick = actions.openAccessibility) { Text(if (tapEnabled) "Accessibility settings" else "Turn on Tap to Send") }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Paused in ${prefs.tapPausedApps.size} banking/UPI app(s)", modifier = Modifier.weight(1f))
            TextButton(onClick = { choosing = true }) { Text("Edit") }
        }
        ToggleRow("Send SMS one-time codes to my Mac’s clipboard", prefs.otpToMac) { on ->
            if (!on) {
                app.settings.setOtpToMac(false)
            } else {
                actions.requestSms { granted ->
                    smsDenied = !granted
                    if (granted) app.settings.setOtpToMac(true)
                }
            }
        }
        if (smsDenied) {
            Text("M’AND needs the SMS permission for this. You can allow it in Settings → Apps → M’AND → Permissions.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        } else if (prefs.otpToMac) {
            Text("Codes are copied on your Mac only if Clipboard sharing is on there.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (choosing) {
        PackagePicker(
            title = "Pause Tap to Send in",
            selected = prefs.tapPausedApps,
            onToggle = { pkg, on -> app.settings.setTapPaused(pkg, on) },
            onDismiss = { choosing = false },
        )
    }
}

@Composable
private fun CallsCard(app: MandApp, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    val result by app.calls.lastResult.collectAsStateWithLifecycle()
    var denied by rememberSaveable { mutableStateOf(false) }
    SectionCard(
        title = "Calls on Mac",
        subtitle = "See who’s calling on your Mac and answer or decline from there. The call itself (audio) stays on your phone.",
    ) {
        ToggleRow("Answer and decline calls from my Mac", prefs.callsEnabled) { on ->
            if (!on) {
                app.settings.setCalls(false)
                app.calls.refresh()
            } else {
                actions.requestCallPermissions { granted ->
                    denied = !granted
                    if (granted) app.settings.setCalls(true)
                }
            }
        }
        if (denied) {
            Text("M’AND needs the Phone permission for this. You can allow it in Settings → Apps → M’AND → Permissions.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        if (prefs.callsEnabled) {
            Text("Tip: with Notification access on, your Mac also shows the caller’s name.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        result?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun FilesCard(app: MandApp, connected: Boolean, actions: FeatureActions) {
    val items by app.files.items.collectAsStateWithLifecycle()
    val canSend = connected && app.client.macSupports(Feature.FILES)
    SectionCard(
        title = "Files",
        subtitle = "Files from your Mac are saved in Downloads/M’AND. You can also use Share → “Send to Mac” in any app.",
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = actions.pickFiles) { Text("Send files to Mac") }
            if (items.any { it.isFinished }) TextButton(onClick = app.files::clearFinished) { Text("Clear finished") }
        }
        if (!canSend) {
            Text(
                if (connected) "Your Mac’s M’AND needs updating to receive files." else "Files you pick now are sent when your Mac connects.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        items.takeLast(6).reversed().forEach { TransferRow(it, onCancel = { app.files.cancel(it.id) }) }
    }
}

@Composable
private fun TransferRow(item: TransferItem, onCancel: () -> Unit) {
    val context = LocalContext.current
    val size = Formatter.formatShortFileSize(context, item.size)
    val detail = when (val state = item.state) {
        TransferState.Preparing -> "Preparing · $size"
        TransferState.Waiting -> "Waiting · $size"
        TransferState.Offered -> "Waiting for the Mac… · $size"
        TransferState.Active -> {
            val done = Formatter.formatShortFileSize(context, item.transferred)
            val speed = if (item.bytesPerSecond > 0) " · ${Formatter.formatShortFileSize(context, item.bytesPerSecond.toLong())}/s" else ""
            "$done of $size$speed"
        }
        TransferState.Interrupted -> "Connection lost — will continue automatically"
        TransferState.Done -> if (item.incoming) "Received · $size" else "Sent · $size"
        TransferState.AlreadyThere -> "Already there — not copied again"
        is TransferState.Failed -> state.reason
        TransferState.Cancelled -> "Cancelled"
    }
    Column(Modifier.padding(top = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                (if (item.incoming) "↓ " else "↑ ") + item.name,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (!item.isFinished) TextButton(onClick = onCancel) { Text("Cancel") }
        }
        if (!item.isFinished && item.size > 0) {
            LinearProgressIndicator(
                progress = { (item.transferred.toFloat() / item.size).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ClipboardCard(app: MandApp, connected: Boolean) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    val notice by app.clipboard.notice.collectAsStateWithLifecycle()
    SectionCard(
        title = "Clipboard",
        subtitle = "Off by default. Text you copy is sent only when you tap Send (or use the “Clipboard to Mac” quick-settings tile).",
    ) {
        ToggleRow("Share clipboard text with my Mac", prefs.clipboardEnabled, app.settings::setClipboard)
        OutlinedButton(
            onClick = { app.clipboard.sendCurrentClip() },
            enabled = prefs.clipboardEnabled && connected,
        ) { Text("Send copied text to Mac") }
        notice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun NotificationsCard(app: MandApp, notificationAccess: Boolean, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    var choosing by rememberSaveable { mutableStateOf(false) }
    SectionCard(
        title = "Notifications on Mac",
        subtitle = "Only apps you choose are shared. Android hides one-time codes from M’AND for your safety.",
    ) {
        ToggleRow("Show phone notifications on my Mac", prefs.notificationsEnabled, app.settings::setNotifications)
        if (prefs.notificationsEnabled) {
            if (!notificationAccess) {
                Text(
                    "Android needs you to allow “Notification access” for M’AND. If Android says the setting is " +
                        "restricted, open App info → ⋮ → “Allow restricted settings” first.",
                    style = MaterialTheme.typography.bodySmall,
                )
                OutlinedButton(onClick = actions.openNotificationAccess) { Text("Open Notification access") }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (prefs.allowedApps.isEmpty()) "No apps chosen yet" else "${prefs.allowedApps.size} app(s) shared",
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { choosing = true }) { Text("Choose apps") }
            }
        }
    }
    if (choosing) AppPicker(app, prefs.allowedApps, onDismiss = { choosing = false })
}

@Composable
private fun AppPicker(app: MandApp, allowed: Set<String>, onDismiss: () -> Unit) =
    PackagePicker("Share notifications from", allowed, { pkg, on -> app.settings.setAppAllowed(pkg, on) }, onDismiss)

@Composable
private fun PackagePicker(title: String, selected: Set<String>, onToggle: (String, Boolean) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val apps = remember {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0))
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != context.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(apps, key = { it.first }) { (pkg, label) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = pkg in selected, onCheckedChange = { onToggle(pkg, it) })
                        Text(label)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun SectionCard(title: String, subtitle: String, content: @Composable () -> Unit) =
    MandCard(title = title, subtitle = subtitle, content = content)
