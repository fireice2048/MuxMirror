package com.termirror.mobile.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Primary = Color(0xFF198754)
private val TerminalGreen = Color(0xFFB7F7C1)
private val TerminalBg = Color(0xFF101318)

private val LightColorScheme = lightColorScheme(
    primary = Primary,
    onPrimary = Color.White,
    background = Color(0xFFF5F6F8),
    surface = Color.White
)

private val DarkColorScheme = darkColorScheme(
    primary = Primary,
    onPrimary = Color.White,
    background = TerminalBg,
    surface = Color(0xFF1A1D24)
)

@Composable
fun TermirrorTheme(
    darkTheme: Boolean = androidx.compose.foundation.isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
        typography = Typography,
        content = content
    )
}
