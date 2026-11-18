package dev.mand.android.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// Monochrome "chrome" design (docs/DESIGN_SYSTEM.md): silver backgrounds, white cards lit from the top, one dark
// hero card, black/white pill buttons. Every text/background pair meets WCAG AA; states are always also in words.
// Dynamic colour is off on purpose so M’AND looks the same on every phone.
private val Ink = Color(0xFF111113)

private val LightColors = lightColorScheme(
    primary = Ink,
    onPrimary = Color.White,
    secondary = Color(0xFF3A3A3C),
    background = Color(0xFFE9E9EC),
    surface = Color(0xFFE9E9EC),
    surfaceContainer = Color(0xFFF7F7F8),
    surfaceContainerHigh = Color(0xFFE2E2E6),
    onSurface = Ink,
    onSurfaceVariant = Color(0xFF55565C),
    outline = Color(0xFF8A8A90),
    error = Color(0xFFB3261E),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFF2F2F4),
    onPrimary = Ink,
    secondary = Color(0xFFC7C7CC),
    background = Color(0xFF0B0B0C),
    surface = Color(0xFF0B0B0C),
    surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerHigh = Color(0xFF2A2A2D),
    onSurface = Color(0xFFF2F2F4),
    onSurfaceVariant = Color(0xFFA9A9AF),
    outline = Color(0xFF6E6E73),
    error = Color(0xFFFF8A80),
)

private val Rounded = Shapes(
    extraSmall = RoundedCornerShape(10.dp),
    small = RoundedCornerShape(14.dp),
    medium = RoundedCornerShape(20.dp),
    large = RoundedCornerShape(28.dp),
    extraLarge = RoundedCornerShape(32.dp),
)

@Composable
fun MandTheme(content: @Composable () -> Unit) {
    val base = Typography()
    // Bolder headings for a confident, friendly look; body sizes unchanged so they follow the phone's font size.
    val type = base.copy(
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.Bold),
        headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
    )
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        typography = type,
        shapes = Rounded,
        content = content,
    )
}

/** Spacing scale (4-pt grid), shared with the Mac's Theme.Space. */
object Space {
    val XS = 4.dp
    val S = 8.dp
    val M = 12.dp
    val L = 16.dp
    val XL = 24.dp
}

/** Brushed-silver page background. */
@Composable
fun pageBrush(): Brush = if (isSystemInDarkTheme()) {
    Brush.verticalGradient(listOf(Color(0xFF1A1A1C), Color(0xFF050506)))
} else {
    Brush.verticalGradient(listOf(Color(0xFFF2F2F4), Color(0xFFCFCFD4)))
}

/** True when the person turned animations off (Settings → Accessibility → Remove animations). */
@Composable
fun animationsOff(): Boolean {
    val context = LocalContext.current
    return remember {
        android.provider.Settings.Global.getFloat(
            context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f,
        ) == 0f
    }
}

/** Cards rise and fade in when the screen opens, one after another (skipped when animations are off). */
@Composable
fun Modifier.entrance(order: Int): Modifier {
    val still = animationsOff()
    var shown by remember { mutableStateOf(still) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(order * 60L)
        shown = true
    }
    val progress by animateFloatAsState(
        if (shown) 1f else 0f,
        spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessLow),
        label = "entrance",
    )
    return graphicsLayer {
        alpha = progress
        translationY = (1f - progress) * 40f
    }
}

/** A white card lit from the top, with a bright top edge (Mac: Card). */
@Composable
fun MandCard(title: String? = null, subtitle: String? = null, content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val fill = if (dark) {
        Brush.verticalGradient(listOf(Color(0xFF2A2A2D), Color(0xFF18181A)))
    } else {
        Brush.verticalGradient(listOf(Color.White, Color(0xFFECECEF)))
    }
    val edge = Brush.verticalGradient(listOf(Color.White.copy(alpha = if (dark) 0.25f else 0.95f), Color.Transparent))
    val shape = RoundedCornerShape(28.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.15f), spotColor = Color.Black.copy(alpha = 0.15f))
            .clip(shape)
            .background(fill)
            .border(1.dp, edge, shape)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(Space.S),
    ) {
        title?.let {
            Text(it, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        }
        subtitle?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        content()
    }
}
