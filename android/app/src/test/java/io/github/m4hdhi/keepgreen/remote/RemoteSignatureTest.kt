package io.github.m4hdhi.keepgreen.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteSignatureTest {
    private val key = "00112233445566778899aabbccddeeff"
    private val vector = "e61ba19958971173e1d8eb4038ff25f241eb73396f25529d28cfd3d602fd5e80"

    @Test
    fun `matches the test vector from the spec`() {
        assertEquals(vector, RemoteSignature.sign(key, "GET", "/v1/status", "1700000000", ""))
    }

    @Test
    fun `builds the message exactly as the spec says`() {
        assertEquals("GET\n/v1/status\n1700000000\n", RemoteSignature.message("get", "/v1/status?x=1", "1700000000", ""))
    }

    @Test
    fun `signs a POST body`() {
        // Computed independently with Python's hmac module.
        assertEquals(
            "fe766457198ca1a48e7c2bffe5d45566f81cac51b13afab2a91f201eb1af73bf",
            RemoteSignature.sign("3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "POST", "/v1/boost", "1793876400", """{"minutes":60}"""),
        )
    }

    @Test
    fun `verify accepts a good signature`() {
        assertTrue(verify(vector, now = 1_700_000_000))
        assertTrue(verify(vector.uppercase(), now = 1_700_000_000))
    }

    @Test
    fun `verify rejects a wrong signature, key or body`() {
        val wrong = vector.replaceRange(0, 1, "f")
        assertFalse(verify(wrong, now = 1_700_000_000))
        assertFalse(RemoteSignature.verify("ffffffffffffffffffffffffffffffff", "GET", "/v1/status", "1700000000", "", vector, 1_700_000_000))
        assertFalse(RemoteSignature.verify(key, "GET", "/v1/status", "1700000000", "{}", vector, 1_700_000_000))
        assertFalse(verify("", now = 1_700_000_000))
    }

    @Test
    fun `verify enforces the 120 second clock skew`() {
        assertTrue(verify(vector, now = 1_700_000_120))
        assertTrue(verify(vector, now = 1_699_999_880))
        assertFalse(verify(vector, now = 1_700_000_121))
        assertFalse(verify(vector, now = 1_699_999_879))
    }

    @Test
    fun `verify rejects a time that isn't a number`() {
        val signature = RemoteSignature.sign(key, "GET", "/v1/status", "soon", "")
        assertFalse(RemoteSignature.verify(key, "GET", "/v1/status", "soon", "", signature, 1_700_000_000))
    }

    private fun verify(signature: String, now: Long) =
        RemoteSignature.verify(key, "GET", "/v1/status", "1700000000", "", signature, now)
}
