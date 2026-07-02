package io.github.teamclouday.androidMic.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF0097A7),       // Cyan 700
    onPrimary = Color.White,
    primaryContainer = Color(0xFFB2EBF2),
    secondary = Color(0xFF1976D2),      // Blue 700
    onSecondary = Color.White,
    tertiary = Color(0xFF26A69A),
    background = Color(0xFFF8FAFC),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFEBF0F5),
    error = Color(0xFFD32F2F),
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF4DD0E1),        // Cyan 300
    onPrimary = Color(0xFF00363F),
    primaryContainer = Color(0xFF00515D),
    secondary = Color(0xFF64B5F6),       // Blue 300
    onSecondary = Color(0xFF003258),
    tertiary = Color(0xFF80CBC4),
    background = Color(0xFF0D1117),
    surface = Color(0xFF161B22),
    surfaceVariant = Color(0xFF1F2937),
    error = Color(0xFFEF5350),
)

@Composable
fun USBLinkMicTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        content = content
    )
}
