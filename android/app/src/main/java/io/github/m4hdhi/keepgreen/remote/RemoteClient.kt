package io.github.m4hdhi.keepgreen.remote

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject

/**
 * Client side of the KeepGreen Remote API, version 1 (docs/remote-api.md).
 *
 * Every call runs on [Dispatchers.IO] and either returns a parsed answer or throws a
 * [RemoteException] whose message can be shown to the user as-is.
 */
class RemoteClient(
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
    private val timeoutMillis: Int = DEFAULT_TIMEOUT_MILLIS,
) {
    /** Unsigned health check. Fails unless KeepGreen answers. */
    suspend fun ping(host: String, port: Int): PingInfo {
        val info = PingInfo.fromJson(send(host, port, "GET", "/v1/ping", body = null, key = null))
        if (info.app != APP_NAME) throw RemoteException(RemoteErrors.NOT_KEEPGREEN, RemoteException.Kind.NotKeepGreen)
        if (info.api > API_VERSION) throw RemoteException(RemoteErrors.NEWER_DESKTOP, RemoteException.Kind.Incompatible)
        return info
    }

    /** Trades the 6-digit code for the shared key. [device] is how the desktop will list this phone. */
    suspend fun pair(host: String, port: Int, code: String, device: String): PairResult {
        val body = JSONObject().put("code", code).put("device", device).toString()
        val json = send(host, port, "POST", "/v1/pair", body, key = null, pairing = true)
        return PairResult.fromJson(json) ?: throw badResponse()
    }

    suspend fun status(desktop: Desktop): DesktopStatus = signed(desktop, "GET", "/v1/status", body = null)

    suspend fun setEnabled(desktop: Desktop, enabled: Boolean): DesktopStatus =
        signed(desktop, "POST", "/v1/enabled", JSONObject().put("enabled", enabled).toString())

    suspend fun boost(desktop: Desktop, minutes: Int): DesktopStatus {
        require(minutes in 1..MAX_BOOST_MINUTES) { "A boost lasts 1 to $MAX_BOOST_MINUTES minutes." }
        return signed(desktop, "POST", "/v1/boost", JSONObject().put("minutes", minutes).toString())
    }

    suspend fun boostUntilEndOfWorkday(desktop: Desktop): DesktopStatus =
        signed(desktop, "POST", "/v1/boost", JSONObject().put("untilEndOfWorkday", true).toString())

    suspend fun cancelBoost(desktop: Desktop): DesktopStatus =
        signed(desktop, "POST", "/v1/boost/cancel", "{}")

    private suspend fun signed(desktop: Desktop, method: String, path: String, body: String?): DesktopStatus =
        DesktopStatus.fromJson(send(desktop.host, desktop.port, method, path, body, desktop.key))

    /**
     * One request on a fresh connection (the desktop closes it after answering).
     * A non-null [key] signs the request; [body] null means no body, which is signed as "".
     */
    private suspend fun send(
        host: String,
        port: Int,
        method: String,
        path: String,
        body: String?,
        key: String?,
        pairing: Boolean = false,
    ): JSONObject = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            val http = URL("http", host, port, path).openConnection() as HttpURLConnection
            connection = http
            http.requestMethod = method
            http.connectTimeout = timeoutMillis
            http.readTimeout = timeoutMillis
            http.useCaches = false
            http.instanceFollowRedirects = false
            http.setRequestProperty("Accept", "application/json")
            http.setRequestProperty("Connection", "close")

            if (key != null) {
                val time = clock().toString()
                http.setRequestProperty(RemoteSignature.HEADER_TIME, time)
                http.setRequestProperty(
                    RemoteSignature.HEADER_SIGNATURE,
                    RemoteSignature.sign(key, method, path, time, body.orEmpty()),
                )
            }

            if (body != null) {
                // Bodies are tiny, so let the connection buffer them and send Content-Length.
                http.doOutput = true
                http.setRequestProperty("Content-Type", "application/json")
                http.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }

            val code = http.responseCode
            val stream = if (code >= 400) http.errorStream else http.inputStream
            val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty()

            if (code !in 200..299) throw httpError(code, pairing)
            try {
                JSONObject(text)
            } catch (e: JSONException) {
                throw badResponse(e)
            }
        } catch (e: RemoteException) {
            throw e
        } catch (e: IOException) {
            throw RemoteException(RemoteErrors.UNREACHABLE, RemoteException.Kind.Unreachable, e)
        } catch (e: IllegalArgumentException) {
            // For example a port out of range, or a host the URL parser rejects.
            throw RemoteException(RemoteErrors.UNREACHABLE, RemoteException.Kind.Unreachable, e)
        } finally {
            connection?.disconnect()
        }
    }

    private fun httpError(code: Int, pairing: Boolean): RemoteException = when (code) {
        401 -> if (pairing) {
            RemoteException(RemoteErrors.BAD_CODE, RemoteException.Kind.BadCode)
        } else {
            RemoteException(RemoteErrors.NOT_TRUSTED, RemoteException.Kind.NotTrusted)
        }
        429 -> RemoteException(RemoteErrors.TOO_MANY_TRIES, RemoteException.Kind.TooManyTries)
        400 -> RemoteException(RemoteErrors.BAD_REQUEST, RemoteException.Kind.Incompatible)
        404, 405 -> RemoteException(RemoteErrors.INCOMPATIBLE, RemoteException.Kind.Incompatible)
        else -> RemoteException(RemoteErrors.unexpected(code))
    }

    private fun badResponse(cause: Throwable? = null) =
        RemoteException(RemoteErrors.BAD_RESPONSE, RemoteException.Kind.BadResponse, cause)

    companion object {
        const val APP_NAME = "KeepGreen"
        const val API_VERSION = 1
        const val MAX_BOOST_MINUTES = 720
        const val DEFAULT_TIMEOUT_MILLIS = 5_000
    }
}
