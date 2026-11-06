package io.github.m4hdhi.keepgreen.remote

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** A computer this phone has paired with. [key] is the shared secret used to sign requests. */
data class Desktop(
    val id: String,
    val host: String,
    val port: Int,
    val key: String,
    val name: String,
    val platform: String,
    val version: String = "",
) {
    /** `host:port`, with IPv6 hosts in brackets. */
    val address: String get() = if (host.contains(':')) "[$host]:$port" else "$host:$port"

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("host", host)
        .put("port", port)
        .put("key", key)
        .put("name", name)
        .put("platform", platform)
        .put("version", version)

    companion object {
        fun fromJson(json: JSONObject): Desktop? {
            val id = json.optString("id")
            val host = json.optString("host")
            val key = json.optString("key")
            val port = json.optInt("port", -1)
            if (id.isEmpty() || host.isEmpty() || key.isEmpty() || port !in 1..65535) return null
            return Desktop(
                id = id,
                host = host,
                port = port,
                key = key,
                name = json.optString("name").ifBlank { host },
                platform = json.optString("platform"),
                version = json.optString("version"),
            )
        }

        fun listToJson(desktops: List<Desktop>): String {
            val array = JSONArray()
            desktops.forEach { array.put(it.toJson()) }
            return array.toString()
        }

        /** Reads a stored list, skipping broken entries. Never throws. */
        fun listFromJson(text: String?): List<Desktop> {
            if (text.isNullOrBlank()) return emptyList()
            return try {
                val array = JSONArray(text)
                (0 until array.length()).mapNotNull { i -> array.optJSONObject(i)?.let { fromJson(it) } }
            } catch (e: JSONException) {
                emptyList()
            }
        }
    }
}
