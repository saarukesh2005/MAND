package dev.mand.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Restrained graphite + mint palette, matching the Mac app icon. Dynamic colour is off on purpose
// so M’AND looks the same on every phone.
private val Mint = Color(0xFF2FA878)
private val MintDark = Color(0xFF5CD69E)

private val LightColors = lightColorScheme(
    primary = Mint,
    onPrimary = Color.White,
    background = Color(0xFFF7F8FA),
    surface = Color(0xFFF7F8FA),
    surfaceContainer = Color(0xFFFFFFFF),
    surfaceContainerHigh = Color(0xFFEFF1F4),
    onSurface = Color(0xFF16181C),
    onSurfaceVariant = Color(0xFF5B616B),
    error = Color(0xFFC4452F),
)

private val DarkColors = darkColorScheme(
    primary = MintDark,
    onPrimary = Color(0xFF07291B),
    background = Color(0xFF111317),
    surface = Color(0xFF111317),
    surfaceContainer = Color(0xFF1B1E23),
    surfaceContainerHigh = Color(0xFF24282E),
    onSurface = Color(0xFFE9EBEE),
    onSurfaceVariant = Color(0xFFA2A8B1),
    error = Color(0xFFFF8A73),
)

@Composable
fun MandTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors, content = content)
}

/** Spacing scale (4-pt grid), shared with the Mac's Theme.Space. */
object Space {
    val XS = 4.dp
    val S = 8.dp
    val M = 12.dp
    val L = 16.dp
    val XL = 24.dp
}

/** Raised surface used for every section (Mac: Card). */
@Composable
fun MandCard(title: String? = null, subtitle: String? = null, content: @Composable () -> Unit) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 1.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(Space.S)) {
            title?.let {
                Text(it, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.semantics { heading() })
            }
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            content()
        }
    }
}
