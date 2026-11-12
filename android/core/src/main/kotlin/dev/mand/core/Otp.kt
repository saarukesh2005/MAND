package dev.mand.core

/**
 * Finds a one-time code in an SMS. Conservative on purpose: the message must say it's a code
 * (OTP, verification code, …), and amounts, phone numbers and long account numbers never count.
 */
object Otp {
    private val KEYWORDS = Regex(
        "\\b(otp|one[ -]?time|verification|verify|passcode|security code|login code|auth(entication)? code|code|pin)\\b",
        RegexOption.IGNORE_CASE,
    )
    /** 4–8 digits, optionally split once by a space or dash ("123 456", "123-456"). */
    private val CANDIDATE = Regex("(?<![\\d₹.,])(\\d{3,4}[ -]\\d{3,4}|\\d{4,8})(?![\\d.,])")
    private val MONEY_BEFORE = Regex("(rs\\.?|inr|₹|\\$|usd|amt|amount)\\s*$", RegexOption.IGNORE_CASE)

    fun find(text: String): String? {
        if (!KEYWORDS.containsMatchIn(text)) return null
        for (m in CANDIDATE.findAll(text)) {
            val before = text.substring(maxOf(0, m.range.first - 8), m.range.first)
            if (MONEY_BEFORE.containsMatchIn(before)) continue
            val digits = m.value.filter(Char::isDigit)
            if (digits.length !in 4..8) continue
            if (looksLikeYear(digits) && !nearKeyword(text, m.range)) continue
            return digits
        }
        return null
    }

    private fun looksLikeYear(d: String) = d.length == 4 && d.toInt() in 1900..2100

    private fun nearKeyword(text: String, range: IntRange): Boolean {
        val window = text.substring(maxOf(0, range.first - 40), minOf(text.length, range.last + 40))
        return KEYWORDS.containsMatchIn(window)
    }
}
