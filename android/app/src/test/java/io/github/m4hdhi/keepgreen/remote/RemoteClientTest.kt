package io.github.m4hdhi.keepgreen.remote

import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Runs the real client against a tiny one-request-per-connection server, like the desktop's. */
class RemoteClientTest {
    private val now = 1_793_876_400L
    private val key = "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1"
    private val client = RemoteClient(clock = { now })

    @Test
    fun `status is signed and parsed`(): Unit = runBlocking {
        FakeDesktop { request ->
            val ok = RemoteSignature.verify(
                key,
                request.method,
                request.path,
                request.headers["x-keepgreen-time"].orEmpty(),
                request.body,
                request.headers["x-keepgreen-signature"].orEmpty(),
                now,
            )
            if (ok) 200 to STATUS else 401 to """{"error":"bad signature"}"""
        }.use { server ->
            val status = client.status(paired(server.port))
            assertEquals("Active", status.state)
            val request = server.requests.single()
            assertEquals("GET", request.method)
            assertEquals("/v1/status", request.path)
            assertEquals(now.toString(), request.headers["x-keepgreen-time"])
        }
    }

    @Test
    fun `boost sends the body it signed`(): Unit = runBlocking {
        FakeDesktop { 200 to STATUS }.use { server ->
            client.boost(paired(server.port), 60)
            val request = server.requests.single()
            assertEquals("POST", request.method)
            assertEquals("/v1/boost", request.path)
            assertEquals("""{"minutes":60}""", request.body)
            assertEquals(
                RemoteSignature.sign(key, "POST", "/v1/boost", now.toString(), request.body),
                request.headers["x-keepgreen-signature"],
            )
        }
    }

    @Test
    fun `pairing returns the key`(): Unit = runBlocking {
        FakeDesktop { 200 to """{"key":"$key","name":"DESKTOP-ABC","platform":"windows","version":"2.0.0"}""" }.use { server ->
            val result = client.pair("127.0.0.1", server.port, "123456", "Test phone")
            assertEquals(key, result.key)
            val body = server.requests.single().body
            assertTrue(body, body.contains("\"code\":\"123456\""))
            assertTrue(body, body.contains("\"device\":\"Test phone\""))
        }
    }

    @Test
    fun `pairing errors become friendly sentences`(): Unit = runBlocking {
        FakeDesktop { 401 to """{"error":"bad code"}""" }.use { server ->
            expectError(RemoteErrors.BAD_CODE) { client.pair("127.0.0.1", server.port, "123456", "Test phone") }
        }
        FakeDesktop { 429 to """{"error":"slow down"}""" }.use { server ->
            expectError(RemoteErrors.TOO_MANY_TRIES) { client.pair("127.0.0.1", server.port, "123456", "Test phone") }
        }
    }

    @Test
    fun `a rejected signature says so`(): Unit = runBlocking {
        FakeDesktop { 401 to """{"error":"bad signature"}""" }.use { server ->
            expectError(RemoteErrors.NOT_TRUSTED) { client.status(paired(server.port)) }
        }
    }

    @Test
    fun `ping rejects something that isn't KeepGreen`(): Unit = runBlocking {
        FakeDesktop { 200 to """{"app":"SomethingElse"}""" }.use { server ->
            expectError(RemoteErrors.NOT_KEEPGREEN) { client.ping("127.0.0.1", server.port) }
        }
    }

    @Test
    fun `an unreachable computer gets the Wi-Fi hint`(): Unit = runBlocking {
        val closedPort = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { it.localPort }
        expectError(RemoteErrors.UNREACHABLE) { client.status(paired(closedPort)) }
    }

    private fun paired(port: Int) = Desktop("id", "127.0.0.1", port, key, "Test PC", "windows")

    private suspend fun expectError(message: String, block: suspend () -> Unit) {
        try {
            block()
            fail("Expected: $message")
        } catch (e: RemoteException) {
            assertEquals(message, e.message)
        }
    }

    private class Request(val method: String, val path: String, val headers: Map<String, String>, val body: String)

    /** Answers each connection with [respond] (status code to JSON body), then closes it. */
    private class FakeDesktop(private val respond: (Request) -> Pair<Int, String>) : Closeable {
        private val server = ServerSocket(0, 10, InetAddress.getLoopbackAddress())
        val port: Int = server.localPort
        val requests = CopyOnWriteArrayList<Request>()

        init {
            thread(isDaemon = true) {
                while (!server.isClosed) {
                    try {
                        server.accept().use { socket -> handle(socket) }
                    } catch (e: IOException) {
                        // Closed by close(), or the client hung up.
                    }
                }
            }
        }

        private fun handle(socket: Socket) {
            val input = socket.getInputStream()
            val requestLine = readLine(input)
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = readLine(input)
                if (line.isEmpty()) break
                headers[line.substringBefore(':').trim().lowercase()] = line.substringAfter(':').trim()
            }
            val length = headers["content-length"]?.toIntOrNull() ?: 0
            val body = ByteArray(length)
            var read = 0
            while (read < length) {
                val n = input.read(body, read, length - read)
                if (n < 0) break
                read += n
            }

            val parts = requestLine.split(' ')
            val request = Request(parts[0], parts.getOrElse(1) { "" }, headers, String(body, 0, read, Charsets.UTF_8))
            requests.add(request)

            val (code, text) = respond(request)
            val bytes = text.toByteArray(Charsets.UTF_8)
            val head = "HTTP/1.1 $code ${reason(code)}\r\n" +
                "Content-Type: application/json\r\n" +
                "Content-Length: ${bytes.size}\r\n" +
                "Connection: close\r\n\r\n"
            val output = socket.getOutputStream()
            output.write(head.toByteArray(Charsets.US_ASCII))
            output.write(bytes)
            output.flush()
        }

        private fun readLine(input: InputStream): String {
            val line = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0 || c == '\n'.code) break
                if (c != '\r'.code) line.append(c.toChar())
            }
            return line.toString()
        }

        private fun reason(code: Int) = when (code) {
            200 -> "OK"
            401 -> "Unauthorized"
            429 -> "Too Many Requests"
            else -> "Error"
        }

        override fun close() {
            server.close()
        }
    }

    private companion object {
        val STATUS = """
            {"name":"DESKTOP-ABC","platform":"windows","version":"2.0.0","state":"Active","isActive":true,
             "isEnabled":true,"isBoosted":false,"boostUntil":null,"headline":"You're staying green",
             "detail":"Work hours end today at 17:00.","idleSeconds":12,"nudgesToday":87,"greenSecondsToday":22320}
        """.trimIndent()
    }
}
