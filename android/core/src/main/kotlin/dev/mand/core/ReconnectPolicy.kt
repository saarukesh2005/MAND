package dev.mand.core

/**
 * How long the phone waits between reconnect rounds. Quick at first (a Mac restarting, Wi-Fi blips),
 * then a slow "resting" pace so a phone away from home doesn't drain its battery retrying.
 * A network change always triggers an immediate retry regardless (handled by the caller).
 */
object ReconnectPolicy {
    /** After this many failed rounds in a row, retry only every [RESTING_DELAY_MS]. */
    const val FAST_ROUNDS = 10
    const val RESTING_DELAY_MS = 5L * 60 * 1000

    fun delayMs(failedRounds: Int): Long =
        if (failedRounds >= FAST_ROUNDS) RESTING_DELAY_MS else ConnectionTiming.backoffMs(failedRounds)

    fun isResting(failedRounds: Int): Boolean = failedRounds >= FAST_ROUNDS
}
