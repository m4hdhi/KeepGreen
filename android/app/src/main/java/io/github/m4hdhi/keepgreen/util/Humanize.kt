package io.github.m4hdhi.keepgreen.util

import java.text.NumberFormat

/** Short, friendly text for durations and counts, matching the desktop app. */
object Humanize {
    /** "42 s", "5 min" or "6 h 12 min". */
    fun duration(totalSeconds: Long): String {
        val seconds = totalSeconds.coerceAtLeast(0)
        if (seconds < 60) return "$seconds s"
        if (seconds < 3600) return "${seconds / 60} min"

        val hours = seconds / 3600
        val minutes = (seconds % 3600) / 60
        return if (minutes == 0L) "$hours h" else "$hours h $minutes min"
    }

    /** Whole number with the phone's digit grouping, e.g. "1,234". */
    fun count(value: Long): String = NumberFormat.getIntegerInstance().format(value)
}
