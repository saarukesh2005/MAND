package dev.mand.android.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.mand.android.tap.TapSetup

/**
 * Tap to Send in one place: an animated picture of what to do, then one big step at a time.
 * Each button opens exactly the Android screen needed, and says in plain words what to press there.
 */
@Composable
internal fun TapGuide(step: TapSetup.Step, connected: Boolean, macReady: Boolean, onStepDone: () -> Unit) {
    val context = LocalContext.current
    HeroPanel {
        TapAnimation(Modifier.fillMaxWidth().height(150.dp).clipToBounds())
        AnimatedContent(
            targetState = step,
            transitionSpec = {
                (slideInHorizontally { it / 3 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 3 } + fadeOut())
            },
            label = "tap-step",
        ) { current ->
            Column(verticalArrangement = Arrangement.spacedBy(Space.M), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
                when (current) {
                    TapSetup.Step.DONE -> {
                        BigTitle(if (macReady) "Ready to tap!" else "Almost ready")
                        BigText(
                            when {
                                !connected -> "Connect to your Mac, then hold the top of this screen on the notch until it buzzes."
                                macReady -> "Open anything. Hold the top of this screen against the black notch on your Mac until the phone buzzes."
                                else -> "Your Mac switches Tap to Send on by itself. If it doesn’t, open M’AND on the Mac → Settings."
                            },
                        )
                    }
                    TapSetup.Step.TRY_ONCE -> {
                        StepLabel(1)
                        BigTitle("Switch on Tap to Send")
                        BigText("Tap the button, then tap “M’AND Tap to Send and control”. If Android says “denied” or “restricted”, that’s expected. Tap Close and come back here.")
                        BigButton("Open the switch") {
                            TapSetup.markTried(context)
                            TapSetup.openServicePage(context)
                            onStepDone()
                        }
                    }
                    TapSetup.Step.ALLOW_RESTRICTED -> {
                        StepLabel(2)
                        BigTitle("Give permission")
                        BigText("Android protects apps installed from a file. Tap the button, then tap ⋮ (top right corner) → “Allow restricted settings”, and confirm.")
                        BigButton("Open App info") {
                            TapSetup.markAllowed(context)
                            TapSetup.openAppInfo(context)
                            onStepDone()
                        }
                        TextButton(onClick = { TapSetup.markAllowed(context); onStepDone() }) {
                            Text("I don’t see ⋮, skip", color = Color.White.copy(alpha = 0.8f))
                        }
                    }
                    TapSetup.Step.TURN_ON -> {
                        StepLabel(3)
                        BigTitle("Turn it on")
                        BigText("Tap the button, tap “M’AND Tap to Send and control”, switch it on, then tap Allow.")
                        BigButton("Open the switch") { TapSetup.openServicePage(context) }
                        TextButton(onClick = { TapSetup.reset(context); onStepDone() }) {
                            Text("Start again", color = Color.White.copy(alpha = 0.8f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StepLabel(number: Int) {
    Text("Step $number of 3", style = MaterialTheme.typography.labelLarge, color = Color.White.copy(alpha = 0.75f))
}

@Composable
private fun BigTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
        color = Color.White,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun BigText(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, color = Color.White.copy(alpha = 0.88f))
}

/** The design's white pill on a dark card. Tall, easy to hit. */
@Composable
private fun BigButton(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) { Text(label, style = MaterialTheme.typography.titleMedium) }
}

/**
 * A looping picture of the gesture: a phone rises to a laptop's notch, its screen flashes white then black,
 * and a check appears. Drawn in code (no image files), described for TalkBack, still when animations are off.
 */
@Composable
private fun TapAnimation(modifier: Modifier) {
    val transition = rememberInfiniteTransition(label = "tap")
    val t by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2600, easing = FastOutSlowInEasing), RepeatMode.Restart),
        label = "t",
    )
    Box(
        modifier.semantics { contentDescription = "Picture: the top of the phone touches the black notch at the top of the Mac’s screen." },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(260.dp, 150.dp)) {
            val w = size.width
            val h = size.height
            // Laptop screen with the notch.
            val screenW = w * 0.78f
            val screenH = h * 0.40f
            val left = (w - screenW) / 2
            drawRoundRect(
                brush = Brush.verticalGradient(listOf(Color(0xFF5A5A5E), Color(0xFF1C1C1E))),
                topLeft = Offset(left, 0f), size = Size(screenW, screenH), cornerRadius = CornerRadius(18f),
            )
            drawRoundRect(
                color = Color.Black, topLeft = Offset(w / 2 - 34f, 0f), size = Size(68f, 16f), cornerRadius = CornerRadius(8f),
            )
            // Phone: rises (0–0.35), holds and flashes (0.35–0.8), drops back (0.8–1).
            val rise = when {
                t < 0.35f -> t / 0.35f
                t < 0.8f -> 1f
                else -> 1f - (t - 0.8f) / 0.2f
            }
            val phoneW = w * 0.16f
            val phoneH = h * 0.62f
            val top = h - phoneH * 0.55f - rise * (h - phoneH * 0.55f - 4f)
            val screen = when {
                t in 0.40f..0.58f -> Color.White
                t in 0.58f..0.78f -> Color.Black
                else -> Color(0xFF8E8E93)
            }
            drawRoundRect(
                brush = Brush.verticalGradient(listOf(Color(0xFFEDEDED), Color(0xFF9A9A9E))),
                topLeft = Offset(w / 2 - phoneW / 2, top), size = Size(phoneW, phoneH), cornerRadius = CornerRadius(14f),
            )
            drawRoundRect(
                color = screen,
                topLeft = Offset(w / 2 - phoneW / 2 + 5f, top + 5f), size = Size(phoneW - 10f, phoneH - 10f), cornerRadius = CornerRadius(10f),
            )
            // The "buzz": a ring around the contact point.
            if (t in 0.62f..0.82f) {
                val p = (t - 0.62f) / 0.2f
                drawCircle(Color.White.copy(alpha = 1f - p), radius = 12f + p * 30f, center = Offset(w / 2, 8f), style = androidx.compose.ui.graphics.drawscope.Stroke(3f))
            }
        }
    }
}

/** A dark chrome card (the design's hero). */
@Composable
internal fun HeroPanel(content: @Composable () -> Unit) {
    androidx.compose.material3.Surface(
        shape = androidx.compose.foundation.shape.RoundedCornerShape(28.dp),
        color = Color.Transparent,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier
                .background(Brush.linearGradient(listOf(Color(0xFF333336), Color(0xFF0A0A0B))))
                .padding(Space.XL),
            verticalArrangement = Arrangement.spacedBy(Space.M),
        ) { content() }
    }
}


@Composable
internal fun SmallRow(content: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) { content() }
}

/** Content on a dark hero card: the dark colour scheme (white text, white buttons), in light and dark mode alike. */
@Composable
internal fun OnDark(content: @Composable () -> Unit) {
    val dark = androidx.compose.material3.darkColorScheme(
        primary = Color(0xFFF2F2F4), onPrimary = Color(0xFF111113),
        onSurface = Color(0xFFF2F2F4), onSurfaceVariant = Color(0xFFC4C4C9),
        outline = Color(0xFF9A9AA0), error = Color(0xFFFF8A80),
    )
    MaterialTheme(colorScheme = dark, typography = MaterialTheme.typography, shapes = MaterialTheme.shapes) {
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides Color(0xFFF2F2F4)) {
            content()
        }
    }
}
