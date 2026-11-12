package dev.mand.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FriendlyTest {
    @Test
    fun `time left needs a real speed and bytes still to go`() {
        assertEquals(5, Friendly.secondsRemaining(100, 50, 10.0))
        assertNull(Friendly.secondsRemaining(100, 50, 0.0))
        assertNull(Friendly.secondsRemaining(100, 100, 10.0))
        assertEquals(11, Friendly.secondsRemaining(101, 0, 10.0))
    }

    @Test
    fun `wording matches the Mac`() {
        assertEquals("a few seconds left", Friendly.timeLeft(4))
        assertEquals("less than a minute left", Friendly.timeLeft(45))
        assertEquals("about a minute left", Friendly.timeLeft(70))
        assertEquals("about 10 minutes left", Friendly.timeLeft(600))
        assertEquals("about an hour left", Friendly.timeLeft(4000))
        assertEquals("about 4 hours left", Friendly.timeLeft(4 * 3600))
        assertEquals("1 app", Friendly.count(1, "app"))
        assertEquals("3 apps", Friendly.count(3, "app"))
    }
}
