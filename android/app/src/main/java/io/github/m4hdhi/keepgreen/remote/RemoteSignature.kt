package io.github.m4hdhi.keepgreen.remote

import java.security.MessageDigest
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.abs

/**
 * Request signing from the KeepGreen Remote API (docs/remote-api.md, "Signed requests").
 *
 * The HMAC key is the UTF-8 bytes of the 32-character hex key string, not the 16 bytes it encodes.
 */
object RemoteSignature {
    const val HEADER_TIME = "X-KeepGreen-Time"
    const val HEADER_SIGNATURE = "X-KeepGreen-Signature"

    /** The server rejects requests whose time is further than this from its own clock. */
    const val MAX_SKEW_SECONDS = 120L

    private const val ALGORITHM = "HmacSHA256"
    private val HEX = "0123456789abcdef".toCharArray()

    /** `METHOD\nPATH\nTIME\nBODY`, with the method upper-cased and any query string dropped. */
    fun message(method: String, path: String, time: String, body: String): String =
        method.uppercase(Locale.ROOT) + "\n" + path.substringBefore('?') + "\n" + time + "\n" + body

    /** Lowercase hex HMAC-SHA256 of [message]. */
    fun sign(key: String, method: String, path: String, time: String, body: String): String {
        val mac = Mac.getInstance(ALGORITHM)
        mac.init(SecretKeySpec(key.toByteArray(Charsets.UTF_8), ALGORITHM))
        return toHex(mac.doFinal(message(method, path, time, body).toByteArray(Charsets.UTF_8)))
    }

    /**
     * Checks a signature the way the desktop does: the time must be within [MAX_SKEW_SECONDS] of
     * [nowSeconds] and the signature must match, compared in constant time.
     */
    fun verify(
        key: String,
        method: String,
        path: String,
        time: String,
        body: String,
        signature: String,
        nowSeconds: Long,
    ): Boolean {
        val sentAt = time.toLongOrNull() ?: return false
        if (abs(nowSeconds - sentAt) > MAX_SKEW_SECONDS) return false

        val expected = sign(key, method, path, time, body).toByteArray(Charsets.US_ASCII)
        val actual = signature.lowercase(Locale.ROOT).toByteArray(Charsets.US_ASCII)
        return MessageDigest.isEqual(expected, actual)
    }

    private fun toHex(bytes: ByteArray): String {
        val out = CharArray(bytes.size * 2)
        bytes.forEachIndexed { i, byte ->
            val value = byte.toInt() and 0xFF
            out[i * 2] = HEX[value ushr 4]
            out[i * 2 + 1] = HEX[value and 0x0F]
        }
        return String(out)
    }
}
