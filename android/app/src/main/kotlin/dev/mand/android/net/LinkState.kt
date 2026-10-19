package dev.mand.android.net

/** What the phone's connection to the Mac is doing right now. Shown directly in the UI. */
sealed interface LinkState {
    /** No Mac paired yet. [notice] explains why, e.g. after the Mac forgot this phone. */
    data class NotPaired(val notice: String? = null) : LinkState

    /** Pairing in progress after scanning the QR code. */
    data class Pairing(val macName: String, val step: Step) : LinkState {
        enum class Step { CONNECTING, WAITING_FOR_APPROVAL }
    }

    /** Paired, trying to reach the Mac. [lastError] is the most recent failure, if any. */
    data class Searching(val macName: String, val attempt: Int, val lastError: String?) : LinkState

    data class Connected(val macName: String, val host: String, val sinceMs: Long) : LinkState

    /** Paired, but the connection service isn't running (user stopped it). */
    data class Paused(val macName: String) : LinkState
}

data class ChatLine(val fromMac: Boolean, val text: String, val atMs: Long)
