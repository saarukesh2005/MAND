package dev.mand.android.ui

import android.content.Intent
import android.content.pm.PackageManager
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.mand.android.MandApp
import dev.mand.android.files.TransferItem
import dev.mand.android.files.TransferState
import dev.mand.core.Feature
import dev.mand.core.Friendly

/** Feature sections of the home screen, simplest first. Shown once a Mac is paired. */
@Composable
fun FeatureCards(app: MandApp, connected: Boolean, notificationAccess: Boolean, actions: FeatureActions, tapEnabled: Boolean = false) {
    FilesCard(app, connected, actions)
    FindAndLinksCard(connected)
    ClipboardCard(app, connected)
    NotificationsCard(app, notificationAccess, actions)
    CallsCard(app, actions)
    TapCard(app, connected, tapEnabled, actions)
    Text(
        "Your battery level, phone model and free storage are shown on your Mac while connected.",
        style = MaterialTheme.typography.bodyMedium,
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
    /** Opens this app's page in Android Settings (to allow a permission that was refused). */
    val openAppSettings: () -> Unit = {},
)

@Composable
private fun FilesCard(app: MandApp, connected: Boolean, actions: FeatureActions) {
    val items by app.files.items.collectAsStateWithLifecycle()
    val canSend = connected && app.client.macSupports(Feature.FILES)
    SectionCard(
        title = "Files",
        subtitle = "Files from your Mac are saved in Downloads → M’AND. In any app you can also tap Share → M’AND.",
    ) {
        ButtonRow {
            OutlinedButton(onClick = actions.pickFiles) { Text("Send files to Mac") }
            if (items.any { it.isFinished }) TextButton(onClick = app.files::clearFinished) { Text("Clear finished") }
        }
        if (!canSend) {
            Hint(if (connected) "Update M’AND on your Mac to send files." else "Files you pick now are sent when your Mac connects.")
        }
        items.takeLast(6).reversed().forEach { TransferRow(it, onCancel = { app.files.cancel(it.id) }) }
    }
}

@Composable
private fun FindAndLinksCard(connected: Boolean) {
    val context = LocalContext.current
    SectionCard(
        title = "Screen, links and find my phone",
        subtitle = "Lost your phone nearby? On your Mac, click “Find My Phone” and it rings loudly, even on silent.",
    ) {
        OutlinedButton(
            onClick = { context.startActivity(android.content.Intent(context, dev.mand.android.screen.ScreenShareActivity::class.java)) },
            enabled = connected,
        ) { Text("Show my screen on Mac") }
        Hint(if (connected) "Your Mac shows your screen over Wi-Fi. Android asks you first, every time." else "Connect to your Mac first to show your screen.")
        Hint("To tap and swipe from your Mac too, turn on Tap to Send below. Your Mac can only control the phone while you are showing your screen.")
        Hint("To open a web page on your Mac: in your browser tap Share → M’AND.")
        Hint("Links sent from your Mac appear as a notification here. Tap it to open the page.")
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
            val left = Friendly.secondsRemaining(item.size, item.transferred, item.bytesPerSecond)
                ?.let { " · ${Friendly.timeLeft(it)}" }.orEmpty()
            "$done of $size$speed$left"
        }
        TransferState.Interrupted -> "Connection lost. It will continue automatically."
        TransferState.Done -> if (item.incoming) "Received · $size" else "Sent · $size"
        TransferState.AlreadyThere -> "Already there, so it wasn’t copied again"
        is TransferState.Failed -> state.reason
        TransferState.Cancelled -> "Cancelled"
    }
    Column(Modifier.padding(top = 10.dp).semantics(mergeDescendants = true) { stateDescription = detail }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                (if (item.incoming) "Receiving: " else "Sending: ") + item.name,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (!item.isFinished) {
                TextButton(onClick = onCancel, modifier = Modifier.semantics { contentDescription = "Cancel ${item.name}" }) {
                    Text("Cancel")
                }
            }
        }
        if (!item.isFinished && item.size > 0) {
            LinearProgressIndicator(
                progress = { (item.transferred.toFloat() / item.size).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ClipboardCard(app: MandApp, connected: Boolean) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    val notice by app.clipboard.notice.collectAsStateWithLifecycle()
    SectionCard(
        title = "Clipboard",
        subtitle = "Off until you turn it on. Text you copy is only sent when you tap “Send copied text to Mac”.",
    ) {
        ToggleRow("Share copied text with my Mac", prefs.clipboardEnabled, app.settings::setClipboard)
        OutlinedButton(onClick = { app.clipboard.sendCurrentClip() }, enabled = prefs.clipboardEnabled && connected) {
            Text("Send copied text to Mac")
        }
        when {
            !prefs.clipboardEnabled -> Hint("Turn on the switch above first.")
            !connected -> Hint("Connect to your Mac first.")
        }
        notice?.let { Hint(it) }
    }
}

@Composable
private fun NotificationsCard(app: MandApp, notificationAccess: Boolean, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    var choosing by rememberSaveable { mutableStateOf(false) }
    SectionCard(
        title = "Notifications on Mac",
        subtitle = "Only the apps you choose are shared. Android keeps one-time codes hidden for your safety.",
    ) {
        ToggleRow("Show phone notifications on my Mac", prefs.notificationsEnabled, app.settings::setNotifications)
        if (prefs.notificationsEnabled) {
            if (!notificationAccess) {
                Hint("To show notifications on your Mac, Android needs your OK. Tap the button, find M’AND in the list and switch it on.")
                OutlinedButton(onClick = actions.openNotificationAccess) { Text("Give notification access") }
                Hint("If Android says the setting is restricted: long-press the M’AND icon → App info → ⋮ (top right) → Allow restricted settings, then try again.")
            }
            ButtonRow {
                Text(
                    if (prefs.allowedApps.isEmpty()) "No apps chosen yet" else "Sharing from ${Friendly.count(prefs.allowedApps.size, "app")}",
                    modifier = Modifier.heightIn(min = 48.dp).wrapContentHeight(),
                )
                TextButton(onClick = { choosing = true }) { Text("Choose apps") }
            }
        }
    }
    if (choosing) {
        PackagePicker("Share notifications from", prefs.allowedApps, { pkg, on -> app.settings.setAppAllowed(pkg, on) }) {
            choosing = false
        }
    }
}

@Composable
private fun CallsCard(app: MandApp, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    val result by app.calls.lastResult.collectAsStateWithLifecycle()
    var denied by rememberSaveable { mutableStateOf(false) }
    SectionCard(
        title = "Calls on Mac",
        subtitle = "See who’s calling on your Mac and answer or decline from there. You still talk on your phone.",
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
        if (denied) PermissionProblem("M’AND needs the Phone permission for this.", actions.openAppSettings)
        if (prefs.callsEnabled) Hint("Tip: with notification access on, your Mac also shows the caller’s name.")
        result?.let { Problem(it) }
    }
}

@Composable
private fun TapCard(app: MandApp, connected: Boolean, tapEnabled: Boolean, actions: FeatureActions) {
    val prefs by app.settings.prefs.collectAsStateWithLifecycle()
    var choosing by rememberSaveable { mutableStateOf(false) }
    var smsDenied by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val macReady by app.tapMacReady.collectAsStateWithLifecycle()
    var step by remember(tapEnabled) { mutableStateOf(dev.mand.android.tap.TapSetup.step(context)) }
    TapGuide(
        step = if (tapEnabled) dev.mand.android.tap.TapSetup.Step.DONE else step,
        connected = connected,
        macReady = macReady,
        onStepDone = { step = dev.mand.android.tap.TapSetup.step(context) },
    )
    SectionCard(
        title = "Tap to Send extras",
        subtitle = "Optional. Tap to Send works without these.",
    ) {
        ButtonRow {
            Text(
                "Stays off in ${Friendly.count(prefs.tapPausedApps.size, "banking app")}",
                modifier = Modifier.heightIn(min = 48.dp).wrapContentHeight(),
            )
            TextButton(onClick = { choosing = true }) { Text("Choose apps") }
        }
        ToggleRow("Copy SMS one-time codes to my Mac", prefs.otpToMac) { on ->
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
            PermissionProblem("M’AND needs the SMS permission for this.", actions.openAppSettings)
        } else if (prefs.otpToMac) {
            Hint("Codes are copied on your Mac only if Clipboard is turned on there.")
        }
    }
    if (choosing) {
        PackagePicker("Keep Tap to Send off in", prefs.tapPausedApps, { pkg, on -> app.settings.setTapPaused(pkg, on) }) {
            choosing = false
        }
    }
}

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
                    // The whole row is one checkbox, so tapping the name works and TalkBack reads it as one control.
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .toggleable(value = pkg in selected, role = Role.Checkbox) { onToggle(pkg, it) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(checked = pkg in selected, onCheckedChange = null)
                        Spacer(Modifier.width(12.dp))
                        Text(label)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

/** A label and a switch that act as one control: tap anywhere on the row, and TalkBack reads the label with the state. */
@Composable
internal fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = checked, role = Role.Switch, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Switch(checked = checked, onCheckedChange = null)
    }
}

/** Buttons that wrap onto a new line instead of squashing when the text is large. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ButtonRow(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.S), verticalArrangement = Arrangement.spacedBy(Space.S)) {
        content()
    }
}

@Composable
internal fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** A problem, marked with an icon as well as colour. */
@Composable
internal fun Problem(text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(20.dp).padding(top = 2.dp))
        Spacer(Modifier.width(Space.S))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.error)
    }
}

/** A refused permission: says so, and offers the one button that fixes it. */
@Composable
private fun PermissionProblem(text: String, openAppSettings: () -> Unit) {
    Problem("$text Tap “Open settings”, then Permissions, and choose Allow.")
    OutlinedButton(onClick = openAppSettings) { Text("Open settings") }
}

@Composable
private fun SectionCard(title: String, subtitle: String, content: @Composable () -> Unit) =
    MandCard(title = title, subtitle = subtitle, content = content)
