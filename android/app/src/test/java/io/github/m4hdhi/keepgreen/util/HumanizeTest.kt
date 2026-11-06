package io.github.m4hdhi.keepgreen.util

import org.junit.Assert.assertEquals
import org.junit.Test

class HumanizeTest {
    @Test
    fun `formats durations like the desktop`() {
        assertEquals("0 s", Humanize.duration(-5))
        assertEquals("42 s", Humanize.duration(42))
        assertEquals("5 min", Humanize.duration(5 * 60 + 59))
        assertEquals("2 h", Humanize.duration(2 * 3600))
        assertEquals("6 h 12 min", Humanize.duration(22_320))
    }
}
