package io.github.m4hdhi.keepgreen.remote

import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import org.json.JSONObject

/** Answer to the unsigned `GET /v1/ping` health check. */
data class PingInfo(
    val app: String,
    val api: Int,
    val name: String,
    val platform: String,
    val version: String,
) {
    companion object {
        fun fromJson(json: JSONObject) = PingInfo(
            app = json.optString("app"),
            api = json.optInt("api"),
            name = json.optString("name"),
            platform = json.optString("platform"),
            version = json.optString("version"),
        )
    }
}

/** Answer to `POST /v1/pair`: the shared key plus the desktop's identity. */
data class PairResult(
    val key: String,
    val name: String,
    val platform: String,
    val version: String,
) {
    companion object {
        private val KEY = Regex("^[0-9a-fA-F]{32}$")

        /** Returns null when the key is missing or isn't 32 hex characters. */
        fun fromJson(json: JSONObject): PairResult? {
            val key = json.optString("key")
            if (!KEY.matches(key)) return null
            return PairResult(
                key = key,
                name = json.optString("name"),
                platform = json.optString("platform"),
                version = json.optString("version"),
            )
        }
    }
}

/** How a status should be coloured: green, grey, or amber for everything else. */
enum class StatusTone {
    Active,
    Disabled,
    Paused;

    companion object {
        fun of(state: String): StatusTone = when (state) {
            "Active" -> Active
            "Disabled" -> Disabled
            else -> Paused
        }
    }
}

/** The status object every signed endpoint returns. */
data class DesktopStatus(
    val name: String,
    val platform: String,
    val version: String,
    val state: String,
    val isActive: Boolean,
    val isEnabled: Boolean,
    val isBoosted: Boolean,
    val boostUntil: OffsetDateTime?,
    val headline: String,
    val detail: String,
    val idleSeconds: Long,
    val nudgesToday: Long,
    val greenSecondsToday: Long,
) {
    val tone: StatusTone get() = StatusTone.of(state)

    /** A couple of words for the state, matching the desktop tray. Unknown states pass through. */
    val shortStatus: String
        get() = when (state) {
            "Active" -> if (isBoosted) "Boosted" else "Active"
            "Disabled" -> "Off"
            "OffSchedule" -> "Off schedule"
            "DayOff" -> "Day off"
            "Break" -> "On a break"
            "Locked" -> "Paused: locked"
            "OnBattery", "LowBattery" -> "Paused: battery"
            "WaitingForApp" -> "Waiting for apps"
            else -> state
        }

    companion object {
        fun fromJson(json: JSONObject) = DesktopStatus(
            name = json.optString("name"),
            platform = json.optString("platform"),
            version = json.optString("version"),
            state = json.optString("state"),
            isActive = json.optBoolean("isActive"),
            isEnabled = json.optBoolean("isEnabled"),
            isBoosted = json.optBoolean("isBoosted"),
            boostUntil = parseTime(json.optNullableString("boostUntil")),
            headline = json.optString("headline"),
            detail = json.optString("detail"),
            idleSeconds = json.optLong("idleSeconds"),
            nudgesToday = json.optLong("nudgesToday"),
            greenSecondsToday = json.optLong("greenSecondsToday"),
        )

        private fun parseTime(text: String?): OffsetDateTime? {
            if (text.isNullOrBlank()) return null
            return try {
                OffsetDateTime.parse(text)
            } catch (e: DateTimeParseException) {
                null
            }
        }
    }
}

/** Platform names as people say them. */
fun platformLabel(platform: String): String = when (platform.lowercase()) {
    "windows" -> "Windows"
    "macos" -> "Mac"
    "" -> "Computer"
    else -> platform.replaceFirstChar { it.uppercase() }
}

/** `optString` turns JSON `null` into the text "null"; this returns a real null instead. */
internal fun JSONObject.optNullableString(name: String): String? =
    if (!has(name) || isNull(name)) null else optString(name)
