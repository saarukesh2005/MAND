package dev.mand.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LinkRulesTest {
    @Test
    fun `only web links with a host are valid`() {
        assertTrue(LinkRules.isValid("https://example.com/path?q=1"))
        assertTrue(LinkRules.isValid("HTTP://Example.com"))
        assertFalse(LinkRules.isValid("file:///sdcard/x"))
        assertFalse(LinkRules.isValid("javascript:alert(1)"))
        assertFalse(LinkRules.isValid("https://"))
        assertFalse(LinkRules.isValid("https://a b"))
    }

    @Test
    fun `extract finds the link in shared text`() {
        assertEquals("https://youtu.be/abc", LinkRules.extract("Watch this https://youtu.be/abc"))
        assertEquals("https://example.com", LinkRules.extract("  https://example.com \n"))
        assertNull(LinkRules.extract("no link here"))
        assertNull(LinkRules.extract("ftp://example.com"))
        assertNull(LinkRules.extract(null))
    }
}
