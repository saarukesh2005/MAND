package dev.mand.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.WifiFind
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private data class OnboardingPage(val icon: ImageVector, val title: String, val body: String)

/**
 * First-launch welcome. The local-network page appears only where Android requires that permission
 * (Android 17+); other permissions are asked later, only when a feature needs them.
 */
@Composable
fun OnboardingScreen(
    needsLocalNetwork: Boolean,
    requestLocalNetwork: () -> Unit,
    onFinish: (pairNow: Boolean) -> Unit,
) {
    val pages = buildList {
        add(OnboardingPage(Icons.Outlined.Devices, "Your phone. Your Mac. One ecosystem.",
            "Send files both ways, share copied text, and see notifications, battery and calls on your Mac."))
        add(OnboardingPage(Icons.Outlined.Lock, "Private by design",
            "M’AND connects directly over your own Wi-Fi, encrypted end to end. No cloud and no account. " +
                "Clipboard, notification and call sharing stay off until you turn them on."))
        if (needsLocalNetwork) {
            add(OnboardingPage(Icons.Outlined.WifiFind, "Find your Mac on Wi-Fi",
                "Android asks before apps can reach devices on your local network. M’AND only uses this to talk to your own Mac."))
        }
    }
    var index by rememberSaveable { mutableIntStateOf(0) }
    val page = pages[index.coerceIn(pages.indices)]
    val isLast = index >= pages.lastIndex

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
        Column(
            Modifier.safeDrawingPadding().padding(Space.XL),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(Modifier.fillMaxWidth().padding(top = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(page.icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(64.dp))
                Spacer(Modifier.height(Space.XL))
                Text(page.title, style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold),
                    textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
                Spacer(Modifier.height(Space.M))
                Text(page.body, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(Space.L))
                Text("Step ${index + 1} of ${pages.size}", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = { onFinish(false) }) { Text("Skip") }
                Spacer(Modifier.weight(1f))
                when {
                    !isLast -> Button(onClick = { index++ }) { Text("Continue") }
                    needsLocalNetwork -> Button(onClick = { requestLocalNetwork(); onFinish(true) }) { Text("Allow and pair") }
                    else -> Button(onClick = { onFinish(true) }) { Text("Pair with my Mac") }
                }
            }
        }
    }
}
