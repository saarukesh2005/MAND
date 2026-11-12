package dev.mand.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class OtpTest {
    @Test
    fun `typical bank and app OTP messages`() {
        assertEquals("482913", Otp.find("482913 is your OTP for HDFC Bank NetBanking. Do not share it with anyone."))
        assertEquals("7731", Otp.find("Your Swiggy verification code is 7731"))
        assertEquals("123456", Otp.find("Use code 123-456 to sign in"))
        assertEquals("904512", Otp.find("OTP: 904 512 for txn of Rs. 2,500.00 at AMAZON. Valid for 3 mins."))
    }

    @Test
    fun `amounts, account numbers and plain messages are not codes`() {
        assertNull(Otp.find("Rs 5000 credited to your account XX1234 on 12-11-2026"))
        assertNull(Otp.find("Meet me at 1930 near the station"))
        assertNull(Otp.find("Call 9876543210 for support"))
        assertNull(Otp.find("Your order 12345678901 has shipped"))
        assertEquals(null, Otp.find("Your code is ready")) // keyword but no number
    }

    @Test
    fun `amount next to a real code is skipped`() {
        assertEquals("5521", Otp.find("Pay ₹1499 using OTP 5521"))
    }
}
