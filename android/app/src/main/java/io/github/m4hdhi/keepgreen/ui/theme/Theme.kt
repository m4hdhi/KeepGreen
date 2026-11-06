package io.github.m4hdhi.keepgreen.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Status colours shared with the desktop apps. */
object StatusColors {
    val Active = Color(0xFF22C55E)
    val Disabled = Color(0xFF94A3B8)
    val Attention = Color(0xFFF59E0B)
}

/** The brand green. Light mode uses a slightly deeper shade as `primary` so green text stays readable on white. */
private val Green = Color(0xFF22C55E)
private val GreenDeep = Color(0xFF16A34A)
private val GreenInk = Color(0xFF052E16)

private val LightColors = lightColorScheme(
    primary = GreenDeep,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCFCE7),
    onPrimaryContainer = Color(0xFF14532D),
    secondary = Color(0xFF3F6B52),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFDCFCE7),
    onSecondaryContainer = Color(0xFF14532D),
    tertiary = Color(0xFFB45309),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFEF3C7),
    onTertiaryContainer = Color(0xFF78350F),
    background = Color(0xFFF5F8F6),
    onBackground = Color(0xFF0F172A),
    surface = Color(0xFFF5F8F6),
    onSurface = Color(0xFF0F172A),
    surfaceVariant = Color(0xFFE3EAE6),
    onSurfaceVariant = Color(0xFF526070),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color.White,
    surfaceContainer = Color(0xFFEDF2EF),
    surfaceContainerHigh = Color(0xFFE6ECE8),
    surfaceContainerHighest = Color(0xFFDFE6E2),
    outline = Color(0xFFB8C4BE),
    outlineVariant = Color(0xFFDDE5E0),
    error = Color(0xFFDC2626),
    onError = Color.White,
    errorContainer = Color(0xFFFEE2E2),
    onErrorContainer = Color(0xFF7F1D1D),
)

private val DarkColors = darkColorScheme(
    primary = Green,
    onPrimary = GreenInk,
    primaryContainer = Color(0xFF14532D),
    onPrimaryContainer = Color(0xFFBBF7D0),
    secondary = Color(0xFF86C9A0),
    onSecondary = GreenInk,
    secondaryContainer = Color(0xFF1C3A2A),
    onSecondaryContainer = Color(0xFFBBF7D0),
    tertiary = Color(0xFFFBBF24),
    onTertiary = Color(0xFF451A03),
    tertiaryContainer = Color(0xFF4A3410),
    onTertiaryContainer = Color(0xFFFDE68A),
    background = Color(0xFF09110D),
    onBackground = Color(0xFFE2E8F0),
    surface = Color(0xFF09110D),
    onSurface = Color(0xFFE2E8F0),
    surfaceVariant = Color(0xFF1A2721),
    onSurfaceVariant = Color(0xFF9AA8B6),
    surfaceContainerLowest = Color(0xFF060C09),
    surfaceContainerLow = Color(0xFF111C17),
    surfaceContainer = Color(0xFF14211B),
    surfaceContainerHigh = Color(0xFF1A2822),
    surfaceContainerHighest = Color(0xFF213029),
    outline = Color(0xFF3B4A43),
    outlineVariant = Color(0xFF223029),
    error = Color(0xFFF87171),
    onError = Color(0xFF450A0A),
    errorContainer = Color(0xFF5B1414),
    onErrorContainer = Color(0xFFFECACA),
)

@Composable
fun KeepGreenTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
