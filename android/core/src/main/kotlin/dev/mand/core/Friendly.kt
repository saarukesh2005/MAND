package dev.mand.core

/** Plain-language wording for numbers shown in the UI (same wording as the Mac's `Friendly`). */
object Friendly {
    /** Whole seconds left at the current speed, or null when there's no reliable speed yet. */
    fun secondsRemaining(size: Long, transferred: Long, bytesPerSecond: Double): Long? {
        if (bytesPerSecond < 1 || size <= transferred) return null
        val seconds = (size - transferred) / bytesPerSecond
        if (!seconds.isFinite() || seconds >= 7 * 24 * 3600) return null
        return kotlin.math.ceil(seconds).toLong()
    }

    fun timeLeft(seconds: Long): String = when {
        seconds < 10 -> "a few seconds left"
        seconds < 60 -> "less than a minute left"
        seconds < 90 -> "about a minute left"
        seconds < 3600 -> "about ${Math.round(seconds / 60.0)} minutes left"
        seconds < 5400 -> "about an hour left"
        else -> "about ${Math.round(seconds / 3600.0)} hours left"
    }

    /** "1 app" / "3 apps". */
    fun count(n: Int, one: String, many: String = one + "s"): String = "$n ${if (n == 1) one else many}"
}
