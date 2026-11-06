package io.github.m4hdhi.keepgreen.remote

import java.net.URLDecoder
import java.net.URLEncoder

/**
 * The pairing link a desktop shows as a QR code:
 * `keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC`.
 *
 * Parsed by hand rather than with `android.net.Uri` so it works in plain JVM unit tests.
 */
data class PairingLink(
    val host: String,
    val port: Int,
    val code: String,
    val name: String,
) {
    fun toUri(): String =
        "$PREFIX?host=${encode(host)}&port=$port&code=$code&name=${encode(name)}"

    companion object {
        const val SCHEME = "keepgreen"
        const val DEFAULT_PORT = 47321
        private const val PREFIX = "$SCHEME://pair"
        private val CODE = Regex("^[0-9]{6}$")

        /** True for exactly six digits. */
        fun isValidCode(code: String): Boolean = CODE.matches(code)

        /** Returns null for anything that isn't a well-formed pairing link. */
        fun parse(link: String): PairingLink? {
            val text = link.trim()
            if (!text.startsWith(PREFIX, ignoreCase = true)) return null

            val rest = text.substring(PREFIX.length).substringBefore('#').removePrefix("/")
            if (!rest.startsWith("?")) return null

            val params = try {
                rest.substring(1)
                    .split('&')
                    .filter { it.isNotEmpty() }
                    .associate { decode(it.substringBefore('=')) to decode(it.substringAfter('=', "")) }
            } catch (e: IllegalArgumentException) {
                return null // malformed %-escape
            }

            val host = params["host"]?.trim().orEmpty()
            if (!HostAddress.isValidHost(host)) return null

            val rawPort = params["port"]
            val port = if (rawPort.isNullOrEmpty()) {
                DEFAULT_PORT
            } else {
                rawPort.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            }

            val code = params["code"].orEmpty()
            if (!isValidCode(code)) return null

            val name = params["name"]?.trim().orEmpty().ifEmpty { host }
            return PairingLink(host, port, code, name)
        }

        private fun decode(text: String): String = URLDecoder.decode(text, "UTF-8")

        private fun encode(text: String): String = URLEncoder.encode(text, "UTF-8").replace("+", "%20")
    }
}
