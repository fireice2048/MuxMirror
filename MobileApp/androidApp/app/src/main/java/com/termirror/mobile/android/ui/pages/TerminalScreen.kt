package com.termirror.mobile.android.ui.pages

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirror.mobile.android.MuxAttach
import com.termirror.mobile.android.core.ServerConfig
import com.termirror.mobile.android.core.TermirrorCore
import com.termirror.mobile.android.core.TmEvent
import com.termirror.mobile.android.ui.components.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

private const val CONNECT_TIMEOUT_MS = 10000L

@Composable
fun TerminalScreen(
    server: ServerConfig,
    muxAttach: MuxAttach?,
    onBack: () -> Unit,
    onOpenMuxNav: () -> Unit
) {
    val context = LocalContext.current
    var phase by remember { mutableStateOf("connecting") }
    var errorText by remember { mutableStateOf("") }
    var sessionId by remember { mutableStateOf(-1L) }
    var controlLocked by remember { mutableStateOf(false) }
    var altLocked by remember { mutableStateOf(false) }
    var keyboardVisible by remember { mutableStateOf(false) }

    val controller = remember { TerminalComposeController() }

    val snapshotFlow = remember { MutableStateFlow(TerminalSnapshot()) }
    val snapshot by snapshotFlow.collectAsState()

    var muxAttachState by remember { mutableStateOf(muxAttach) }

    DisposableEffect(server) {
        val listener: (TmEvent) -> Unit = { event ->
            if (event.sessionId == sessionId) {
            when (event.type) {
                "connectionState" -> when (event.state) {
                    "connecting" -> {
                        phase = "connecting"
                        errorText = ""
                    }
                    "connected" -> {
                        phase = "connected"
                        // 连接成功后若指定了 mux attach 则写入命令
                        muxAttachState?.let { attach ->
                            attachToMux(sessionId, attach.mux, attach.session)
                            muxAttachState = null
                        }
                    }
                    "failed" -> {
                        phase = "failed"
                        errorText = event.data ?: "SSH 连接失败"
                    }
                    "closed" -> {
                        phase = "failed"
                        errorText = "会话已关闭"
                    }
                }
                "error" -> {
                    phase = "failed"
                    errorText = event.data ?: "未知错误"
                }
                "output" -> {
                    snapshotFlow.update {
                        it.copy(
                            text = event.data ?: "",
                            cursorOffset = event.cursor ?: (event.data ?: "").length,
                            styles = event.styles,
                            mouseProtocol = event.mouseProtocol
                        )
                    }
                }
            }
            }
        }
        TermirrorCore.addEventListener(listener)

        phase = "connecting"
        errorText = ""
        sessionId = TermirrorCore.connectSession(server, 100, 32)
        if (sessionId <= 0) {
            phase = "failed"
            errorText = "会话创建失败"
        } else {
            val handler = android.os.Handler(android.os.Looper.getMainLooper())
            val timeout = Runnable {
                if (phase == "connecting") {
                    phase = "failed"
                    errorText = "连接超时"
                    TermirrorCore.closeSession(sessionId)
                }
            }
            handler.postDelayed(timeout, CONNECT_TIMEOUT_MS)
        }

        onDispose {
            TermirrorCore.removeEventListener(listener)
            if (sessionId > 0) TermirrorCore.closeSession(sessionId)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(server.name.ifBlank { server.host }, fontSize = 16.sp)
                        Text("ssh ${server.username}@${server.host}:${server.port}", fontSize = 12.sp)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    // 已通过导航页 attach 到 mux 会话时，隐藏 MUX 入口，避免重复 attach
                    if (muxAttach == null) {
                        TextButton(
                            onClick = onOpenMuxNav,
                            enabled = phase == "connected"
                        ) { Text("MUX...") }
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when (phase) {
                "connected" -> {
                    Column(modifier = Modifier.fillMaxSize().imePadding()) {
                        TerminalComposeView(
                            controller = controller,
                            snapshot = snapshot.text,
                            cursorOffset = snapshot.cursorOffset,
                            styles = snapshot.styles,
                            mouseProtocol = TerminalMouseProtocol.fromWire(snapshot.mouseProtocol),
                            onInput = { data ->
                                if (sessionId > 0) TermirrorCore.writeSession(sessionId, data)
                            },
                            onResize = { cols, rows ->
                                if (sessionId > 0) TermirrorCore.resizeSession(sessionId, cols, rows)
                            },
                            onFocusChanged = { focused -> keyboardVisible = focused },
                            modifier = Modifier.weight(1f)
                        )
                        TerminalToolbar(
                            controlLocked = controlLocked,
                            altLocked = altLocked,
                            modifier = Modifier.fillMaxWidth(),
                            onKeyAction = { key ->
                                when (key) {
                                    ToolbarKey.CTRL -> controlLocked = !controlLocked
                                    ToolbarKey.ALT -> altLocked = !altLocked
                                    ToolbarKey.KBD -> {
                                        keyboardVisible = !keyboardVisible
                                        if (keyboardVisible) controller.focus() else controller.blur()
                                    }
                                    ToolbarKey.PAST -> {
                                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                        val text = clipboard.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                                        if (text.isNotEmpty()) controller.paste(text)
                                    }
                                    else -> controller.handleToolKey(key)
                                }
                            }
                        )
                    }
                }
                else -> {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
                    ) {
                        if (phase == "connecting") {
                            CircularProgressIndicator()
                            Spacer(Modifier.height(12.dp))
                        }
                        Text(
                            if (phase == "connecting") "Loading · 正在连接 ${server.host}:${server.port}" else errorText,
                            fontSize = 14.sp
                        )
                        TextButton(onClick = onBack) { Text("返回服务器列表") }
                    }
                }
            }
        }
    }
}

private data class TerminalSnapshot(
    val text: String = "",
    val cursorOffset: Int = 0,
    val styles: List<com.termirror.mobile.android.core.TerminalStyleRange> = emptyList(),
    val mouseProtocol: String = "none"
)

/** 生成从交互式 shell 进入指定 MUX 会话的命令。 */
internal fun buildMuxAttachCommand(mux: String, session: String): String {
    val prefix = if (mux.equals("RMUX", ignoreCase = true)) "rmux" else "tmux"
    val muxEnvironment = "\${TMUX-}\${RMUX_SESSION-}\${RMUX-}"
    val target = shellQuote(session)
    val clientTty = "\${SSH_TTY:-\$(tty 2>/dev/null)}"
    // 共享 pane 内无法判断输入来自哪个 client，禁止无 -c 的 switch-client。
    // 页面必须为目标会话新建 SSH PTY；若生命周期异常导致仍在 MUX 内，则安全拒绝。
    return "if [ -n \"$muxEnvironment\" ]; then " +
        "printf '%s\\n' 'TermMirror: refusing MUX attach from inside an existing MUX session' >&2; " +
        "else " +
        // ignore-size 下共享 window 可能高于手机 PTY，tmux 默认展示顶部裁剪区。
        // attach 注册 client 后在约 2 秒内重复下移该 TTY 的可见区域，避免 tmux
        // 初始化阶段把第一次 refresh 覆盖掉；不改变共享 window 尺寸。
        "(client_tty=\"$clientTty\"; " +
        "for i in 1 2 3 4 5 6 7 8 9 10; do " +
        "client=\$($prefix list-clients -F '#{client_tty}' 2>/dev/null | " +
        "grep -F -x \"\$client_tty\" | head -n 1); " +
        "if [ -n \"\$client\" ]; then " +
        "$prefix refresh-client -t \"\$client\" -D 999 >/dev/null 2>&1; " +
        "fi; sleep 0.2; done) & " +
        "exec $prefix attach-session -f ignore-size -t $target; fi"
}

private fun shellQuote(value: String): String {
    return "'${value.replace("'", "'\"'\"'")}'"
}

private fun attachToMux(sessionId: Long, mux: String, session: String) {
    TermirrorCore.writeSession(sessionId, "${buildMuxAttachCommand(mux, session)}\r")
}
