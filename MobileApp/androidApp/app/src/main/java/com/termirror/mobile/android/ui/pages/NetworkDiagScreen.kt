package com.termirror.mobile.android.ui.pages

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirror.mobile.android.core.TermirrorCore
import com.termirror.mobile.android.core.TmEvent

private val TerminalGreen = Color(0xFFB7F7C1)
private val TerminalBg = Color(0xFF101318)

@Composable
fun NetworkDiagScreen(onBack: () -> Unit) {
    var output by remember { mutableStateOf("网络诊断 已就绪。\n$ ") }
    var input by remember { mutableStateOf("") }
    val scrollState = rememberScrollState()

    DisposableEffect(Unit) {
        val listener: (TmEvent) -> Unit = { event ->
            if (event.type == "diag") {
                output += "${event.data ?: ""}\n$ "
            }
        }
        TermirrorCore.addEventListener(listener)
        onDispose { TermirrorCore.removeEventListener(listener) }
    }

    LaunchedEffect(output) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("网络诊断", color = TerminalGreen) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回", tint = TerminalGreen)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TerminalBg)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(TerminalBg)
                .padding(padding)
                .padding(16.dp)
        ) {
            Text(
                text = output,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(scrollState),
                color = TerminalGreen,
                fontSize = 12.sp,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
            )
            Spacer(Modifier.height(8.dp))
            val sendCommand: () -> Unit = {
                val command = input
                input = ""
                val result = runCommand(command) { host, port -> TermirrorCore.tcpCheck(host, port) }
                output += "$command\n$result"
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .imePadding(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    modifier = Modifier.weight(1f),
                    placeholder = {
                        Text(
                            "tcp <IP/域名> [端口]，例如：\ntcp 192.168.1.1 80\ntcp baidu.com 443",
                            color = TerminalGreen.copy(alpha = 0.6f)
                        )
                    },
                    textStyle = androidx.compose.ui.text.TextStyle(color = TerminalGreen),
                    minLines = 3,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Ascii,
                        imeAction = ImeAction.Send,
                        capitalization = KeyboardCapitalization.None
                    ),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                        onSend = { sendCommand() }
                    ),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = TerminalGreen,
                        unfocusedBorderColor = TerminalGreen.copy(alpha = 0.5f)
                    )
                )
                Spacer(Modifier.width(8.dp))
                Button(onClick = sendCommand) {
                    Text("发送")
                }
            }
        }
    }
}

private fun runCommand(command: String, onTcpCheck: (String, Int) -> Unit): String {
    val parts = command.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    if (parts.size < 2 || parts.size > 3 || parts[0].lowercase() != "tcp") {
        return "Android 网络诊断仅支持 TCP 检测。\n用法：tcp <IP/域名> [端口]\n$ "
    }
    val host = parts[1]
    val port = parts.getOrNull(2)?.toIntOrNull() ?: 443
    if (port !in 1..65535) {
        return "端口必须在 1 到 65535 之间\n$ "
    }
    onTcpCheck(host, port)
    return ""
}
