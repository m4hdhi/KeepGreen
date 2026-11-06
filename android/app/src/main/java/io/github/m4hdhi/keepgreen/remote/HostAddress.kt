package io.github.m4hdhi.keepgreen.remote

/**
 * What someone typed into the address box. The desktop shows addresses like `192.168.1.20:47321`,
 * so a port typed after the host is picked up here.
 */
data class HostAddress(val host: String, val port: Int?) {
    companion object {
        private val FORBIDDEN = setOf('/', '?', '#', '@', '[', ']')

        /**
         * Accepts `192.168.1.20`, `192.168.1.20:47321`, `my-pc.local`, `http://my-pc.local:47321/`
         * and `[fe80::1]:47321`. Returns null when it can't be an address.
         */
        fun parse(input: String): HostAddress? {
            var text = input.trim()
            for (scheme in listOf("http://", "https://")) {
                if (text.startsWith(scheme, ignoreCase = true)) text = text.substring(scheme.length)
            }
            text = text.substringBefore('/')
            if (text.isEmpty()) return null

            if (text.startsWith("[")) {
                val end = text.indexOf(']')
                if (end < 0) return null
                val host = text.substring(1, end)
                val after = text.substring(end + 1)
                val port = when {
                    after.isEmpty() -> null
                    after.startsWith(":") -> parsePort(after.substring(1)) ?: return null
                    else -> return null
                }
                return if (isValidHost(host)) HostAddress(host, port) else null
            }

            // One colon means host:port. More than one is a bare IPv6 address.
            if (text.count { it == ':' } == 1) {
                val host = text.substringBefore(':')
                val port = parsePort(text.substringAfter(':')) ?: return null
                return if (isValidHost(host)) HostAddress(host, port) else null
            }
            return if (isValidHost(text)) HostAddress(text, null) else null
        }

        fun isValidHost(host: String): Boolean =
            host.isNotEmpty() && host.length <= 253 && host.none { it.isWhitespace() || it in FORBIDDEN }

        private fun parsePort(text: String): Int? = text.toIntOrNull()?.takeIf { it in 1..65535 }
    }
}
