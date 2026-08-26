package com.termirror.mobile.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.termirror.mobile.android.core.ServerConfig
import com.termirror.mobile.android.core.TermirrorCore
import com.termirror.mobile.android.ui.pages.MuxNavScreen
import com.termirror.mobile.android.ui.pages.NetworkDiagScreen
import com.termirror.mobile.android.ui.pages.ServerListScreen
import com.termirror.mobile.android.ui.pages.SettingsScreen
import com.termirror.mobile.android.ui.pages.TerminalScreen
import com.termirror.mobile.android.ui.theme.TermirrorTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TermirrorTheme {
                TermirrorApp()
            }
        }
    }
}

@Composable
fun TermirrorApp() {
    val navController = rememberNavController()
    NavHost(navController = navController, startDestination = "serverList") {
        composable("serverList") {
            ServerListScreen(
                onOpenServer = { server ->
                    navController.navigate("terminal/${encodeServerConfig(server)}/none")
                },
                onOpenNetworkDiag = { navController.navigate("networkDiag") },
                onOpenSettings = { navController.navigate("settings") }
            )
        }
        composable("settings") {
            SettingsScreen(onBack = { navController.popBackStack() })
        }
        composable(
            route = "terminal/{config}/{muxAttach}",
            arguments = listOf(
                navArgument("config") { type = ServerConfigNavType },
                navArgument("muxAttach") { defaultValue = MUX_ATTACH_NONE }
            )
        ) { backStackEntry ->
            val server = backStackEntry.arguments?.getParcelable<ServerConfig>("config")
                ?: return@composable
            val muxAttach = decodeMuxAttach(
                backStackEntry.arguments?.getString("muxAttach") ?: MUX_ATTACH_NONE
            )
            TerminalScreen(
                server = server,
                muxAttach = muxAttach,
                onBack = { navController.popBackStack() },
                onOpenMuxNav = { navController.navigate("muxNav/${encodeServerConfig(server)}") }
            )
        }
        composable(
            route = "muxNav/{config}",
            arguments = listOf(navArgument("config") { type = ServerConfigNavType })
        ) { backStackEntry ->
            val server = backStackEntry.arguments?.getParcelable<ServerConfig>("config")
                ?: return@composable
            MuxNavScreen(
                server = server,
                onSelect = { mux, session ->
                    // 选中目录后在导航页之上压入新的终端页（携带 attach 目标），
                    // 返回键先回到导航页，再退到进入导航前的终端页，不会直接回首页。
                    navController.navigate(
                        "terminal/${encodeServerConfig(server)}/${encodeMuxAttach(mux, session)}"
                    )
                },
                onBack = { navController.popBackStack() }
            )
        }
        composable("networkDiag") {
            NetworkDiagScreen(onBack = { navController.popBackStack() })
        }
    }
}

private fun encodeServerConfig(config: ServerConfig): String {
    return listOf(
        config.name,
        config.host,
        config.port.toString(),
        config.username,
        config.password
    ).joinToString("\u001F") // 使用 Unit Separator 分隔，避免与字段内容冲突
}

private fun decodeServerConfig(value: String): ServerConfig {
    val parts = value.split("\u001F")
    return ServerConfig(
        name = parts.getOrElse(0) { "" },
        host = parts.getOrElse(1) { "" },
        port = parts.getOrElse(2) { "22" }.toIntOrNull() ?: 22,
        username = parts.getOrElse(3) { "" },
        password = parts.getOrElse(4) { "" }
    )
}

private const val MUX_ATTACH_NONE = "none"

private fun encodeMuxAttach(mux: String, session: String): String {
    return listOf(mux, session).joinToString("\u001F")
}

private fun decodeMuxAttach(value: String): MuxAttach? {
    if (value == MUX_ATTACH_NONE) return null
    val parts = value.split("\u001F")
    return MuxAttach(
        mux = parts.getOrElse(0) { "" },
        session = parts.getOrElse(1) { "" }
    )
}

val ServerConfigNavType = object : androidx.navigation.NavType<ServerConfig>(isNullableAllowed = false) {
    override fun get(bundle: Bundle, key: String): ServerConfig? {
        @Suppress("DEPRECATION")
        return bundle.getParcelable(key)
    }

    override fun parseValue(value: String): ServerConfig {
        return decodeServerConfig(value)
    }

    override fun put(bundle: Bundle, key: String, value: ServerConfig) {
        bundle.putParcelable(key, value)
    }
}
