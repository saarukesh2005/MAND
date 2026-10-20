package dev.mand.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.mand.android.net.LinkState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Compose UI tests on the JVM (Robolectric). Each LinkState must show the right status and action. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = android.app.Application::class)
class StatusAndOnboardingTest {
    @get:Rule val compose = createComposeRule()

    private val calls = mutableListOf<String>()
    private val actions = HomeActions(
        scanQr = { calls += "scan" },
        requestNotifications = { calls += "notifications" },
        requestBatteryExemption = { calls += "battery" },
        requestLocalNetwork = { calls += "localNetwork" },
        resume = { calls += "resume" },
        pause = { calls += "pause" },
        retry = { calls += "retry" },
    )

    private fun show(state: LinkState, code: String? = "B3EA CD33 433B") {
        compose.setContent { MandTheme { StatusHero(state, code, actions) } }
    }

    @Test
    fun notPaired_offersPairing() {
        show(LinkState.NotPaired())
        compose.onNodeWithText("Pair with your Mac").assertIsDisplayed()
        compose.onNodeWithText("Pair with Mac").performClick()
        assertEquals(listOf("scan"), calls)
    }

    @Test
    fun connected_showsMacNameAndAccessibleStatus() {
        show(LinkState.Connected("Studio Mac", "10.0.0.5", 0))
        compose.onNodeWithText("Studio Mac").assertIsDisplayed()
        compose.onNodeWithContentDescription("Status: Connected").assertIsDisplayed()
    }

    @Test
    fun needsPermission_asksForNearbyDevices() {
        show(LinkState.NeedsPermission("Studio Mac"))
        compose.onNodeWithText("One permission needed").assertIsDisplayed()
        compose.onNodeWithText("Allow Nearby devices").performClick()
        assertTrue("localNetwork" in calls)
    }

    @Test
    fun restingSearch_offersTryAgain() {
        show(LinkState.Searching("Studio Mac", attempt = 12, lastError = null, resting = true))
        compose.onNodeWithText("Can’t reach Studio Mac").assertIsDisplayed()
        compose.onNodeWithText("Try again now").performClick()
        assertEquals(listOf("retry"), calls)
    }

    @Test
    fun offline_explainsWaiting() {
        show(LinkState.Offline("Studio Mac"))
        compose.onNodeWithText("No network").assertIsDisplayed()
    }

    @Test
    fun waitingForApproval_showsSecurityCode() {
        show(LinkState.Pairing("Studio Mac", LinkState.Pairing.Step.WAITING_FOR_APPROVAL))
        compose.onNodeWithText("Approve on your Mac").assertIsDisplayed()
        compose.onNodeWithText("B3EA CD33 433B", substring = true).assertIsDisplayed()
    }

    @Test
    fun onboarding_walksThroughToPairing() {
        var finished: Boolean? = null
        compose.setContent {
            MandTheme { OnboardingScreen(needsLocalNetwork = false, requestLocalNetwork = {}, onFinish = { finished = it }) }
        }
        compose.onNodeWithText("Step 1 of 2").assertIsDisplayed()
        compose.onNodeWithText("Continue").performClick()
        compose.onNodeWithText("Private by design").assertIsDisplayed()
        compose.onNodeWithText("Pair with my Mac").performClick()
        assertEquals(true, finished)
    }

    @Test
    fun onboarding_onAndroid17_requestsLocalNetwork() {
        var requested = false
        compose.setContent {
            MandTheme { OnboardingScreen(needsLocalNetwork = true, requestLocalNetwork = { requested = true }, onFinish = {}) }
        }
        compose.onNodeWithText("Step 1 of 3").assertIsDisplayed()
        repeat(2) { compose.onNodeWithText("Continue").performClick() }
        compose.onNodeWithText("Allow and pair").performClick()
        assertTrue(requested)
    }

    @Test
    fun onboarding_skipDoesNotPair() {
        var finished: Boolean? = null
        compose.setContent {
            MandTheme { OnboardingScreen(needsLocalNetwork = false, requestLocalNetwork = {}, onFinish = { finished = it }) }
        }
        compose.onNodeWithText("Skip").performClick()
        assertEquals(false, finished)
    }
}
