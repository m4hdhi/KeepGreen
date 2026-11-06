package io.github.m4hdhi.keepgreen.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PairingLinkTest {
    @Test
    fun `parses the link from the spec`() {
        val link = PairingLink.parse("keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC")
        assertEquals(PairingLink("192.168.1.20", 47321, "123456", "Mahdhi’s PC"), link)
    }

    @Test
    fun `round-trips through toUri`() {
        val original = PairingLink("my-pc.local", 50000, "007007", "Büro & Home+1 ✓")
        assertEquals(original, PairingLink.parse(original.toUri()))
    }

    @Test
    fun `fills in a missing port and name`() {
        assertEquals(
            PairingLink("10.0.0.5", PairingLink.DEFAULT_PORT, "654321", "10.0.0.5"),
            PairingLink.parse("keepgreen://pair?host=10.0.0.5&code=654321"),
        )
    }

    @Test
    fun `accepts a trailing slash and any parameter order`() {
        assertEquals(
            PairingLink("10.0.0.5", 47321, "654321", "PC"),
            PairingLink.parse("keepgreen://pair/?name=PC&code=654321&port=47321&host=10.0.0.5"),
        )
    }

    @Test
    fun `rejects bad codes`() {
        for (code in listOf("", "12345", "1234567", "12345a", "12 456", "١٢٣٤٥٦")) {
            assertNull("code '$code'", PairingLink.parse("keepgreen://pair?host=10.0.0.5&code=$code"))
        }
        assertNull(PairingLink.parse("keepgreen://pair?host=10.0.0.5"))
    }

    @Test
    fun `rejects bad hosts, ports and other links`() {
        assertNull(PairingLink.parse("keepgreen://pair?code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=evil.com/x&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=10.0.0.5&port=0&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=10.0.0.5&port=70000&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=10.0.0.5&port=abc&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pairing?host=10.0.0.5&code=123456"))
        assertNull(PairingLink.parse("https://example.com/pair?host=10.0.0.5&code=123456"))
        assertNull(PairingLink.parse("keepgreen://pair?host=10.0.0.5&code=123456&name=%E2%8"))
    }
}
