package io.github.m4hdhi.keepgreen.remote

import java.time.OffsetDateTime
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteModelsTest {
    @Test
    fun `parses the status sample from the spec`() {
        val status = DesktopStatus.fromJson(JSONObject(SPEC_STATUS))
        assertEquals("DESKTOP-ABC", status.name)
        assertEquals("windows", status.platform)
        assertEquals("2.0.0", status.version)
        assertEquals("Active", status.state)
        assertTrue(status.isActive)
        assertTrue(status.isEnabled)
        assertFalse(status.isBoosted)
        assertNull(status.boostUntil)
        assertEquals("You're staying green", status.headline)
        assertEquals("Work hours end today at 17:00.", status.detail)
        assertEquals(12L, status.idleSeconds)
        assertEquals(87L, status.nudgesToday)
        assertEquals(22320L, status.greenSecondsToday)
        assertEquals(StatusTone.Active, status.tone)
    }

    @Test
    fun `parses a boost time with its offset`() {
        val json = JSONObject(SPEC_STATUS).put("isBoosted", true).put("boostUntil", "2026-11-05T14:30:00+04:00")
        val status = DesktopStatus.fromJson(json)
        assertEquals(OffsetDateTime.parse("2026-11-05T14:30:00+04:00"), status.boostUntil)
        assertEquals("Boosted", status.shortStatus)
    }

    @Test
    fun `tolerates fractional seconds and an unreadable boost time`() {
        val json = JSONObject(SPEC_STATUS).put("greenSecondsToday", 22320.7).put("boostUntil", "later")
        val status = DesktopStatus.fromJson(json)
        assertEquals(22320L, status.greenSecondsToday)
        assertNull(status.boostUntil)
    }

    @Test
    fun `colours states like the desktop`() {
        assertEquals(StatusTone.Active, StatusTone.of("Active"))
        assertEquals(StatusTone.Disabled, StatusTone.of("Disabled"))
        for (state in listOf("OffSchedule", "DayOff", "Break", "Locked", "OnBattery", "LowBattery", "WaitingForApp", "SomethingNew")) {
            assertEquals(state, StatusTone.Paused, StatusTone.of(state))
        }
    }

    @Test
    fun `parses ping and pair answers`() {
        val ping = PingInfo.fromJson(JSONObject("""{"app": "KeepGreen", "api": 1, "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}"""))
        assertEquals(PingInfo("KeepGreen", 1, "DESKTOP-ABC", "windows", "2.0.0"), ping)

        val pair = PairResult.fromJson(JSONObject("""{"key": "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}"""))
        assertEquals(PairResult("3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "DESKTOP-ABC", "windows", "2.0.0"), pair)

        assertNull(PairResult.fromJson(JSONObject("""{"key": "too-short"}""")))
        assertNull(PairResult.fromJson(JSONObject("""{"name": "DESKTOP-ABC"}""")))
    }

    @Test
    fun `stored desktops survive a round trip and broken entries are skipped`() {
        val desktops = listOf(
            Desktop("a", "192.168.1.20", 47321, "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "Work PC", "windows", "2.0.0"),
            Desktop("b", "fe80::1", 47321, "00112233445566778899aabbccddeeff", "Mac", "macos"),
        )
        assertEquals(desktops, Desktop.listFromJson(Desktop.listToJson(desktops)))
        assertEquals("[fe80::1]:47321", desktops[1].address)

        assertEquals(emptyList<Desktop>(), Desktop.listFromJson("not json"))
        assertEquals(emptyList<Desktop>(), Desktop.listFromJson(null))
        assertEquals(1, Desktop.listFromJson("""[{"id": "x"}, ${desktops[0].toJson()}]""").size)
    }

    companion object {
        private val SPEC_STATUS = """
            {
              "name": "DESKTOP-ABC",
              "platform": "windows",
              "version": "2.0.0",
              "state": "Active",
              "isActive": true,
              "isEnabled": true,
              "isBoosted": false,
              "boostUntil": null,
              "headline": "You're staying green",
              "detail": "Work hours end today at 17:00.",
              "idleSeconds": 12,
              "nudgesToday": 87,
              "greenSecondsToday": 22320
            }
        """.trimIndent()
    }
}
