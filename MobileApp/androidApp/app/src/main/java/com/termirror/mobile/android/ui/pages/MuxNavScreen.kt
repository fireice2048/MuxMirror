package com.termirror.mobile.android.ui.pages

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirror.mobile.android.core.ServerConfig
import com.termirror.mobile.android.core.SettingsStore
import com.termirror.mobile.android.core.TermirrorCore
import com.termirror.mobile.android.core.TmEvent
import org.json.JSONObject
import org.json.JSONArray

@Composable
fun MuxNavScreen(
    server: ServerConfig,
    onSelect: (String, String) -> Unit,
    onBack: () -> Unit
) {
    var loading by remember { mutableStateOf(true) }
    var errorMsg by remember { mutableStateOf("") }
    var items by remember { mutableStateOf(listOf<NavItem>()) }
    var retryCount by remember { mutableStateOf(0) }
    var execId by remember { mutableStateOf(-1L) }
    val context = LocalContext.current
    val groupingMode = SettingsStore.getMuxGroupingMode(context)
    var useServerDirectory by remember { mutableStateOf(groupingMode == SettingsStore.GROUPING_DIRECTORY) }

    DisposableEffect(server) {
        val listener = listener@{ event: TmEvent ->
            if (event.type == "execResult" && event.sessionId == execId) {
                if (event.state == "ok") {
                    val result = parseMuxResult(event.data ?: "", groupingMode, useServerDirectory)
                    if (result.isEmpty() && useServerDirectory) {
                        // 服务端可能还不支持 --by-directory，退回到客户端分组。
                        useServerDirectory = false
                        retryCount = 0
                        runQuery(context, server, groupingMode, useServerDirectory) { execId = it }
                        return@listener
                    }
                    items = result
                    loading = false
                    errorMsg = if (result.isEmpty()) "没有终端窗口" else ""
                } else if (useServerDirectory) {
                    // 服务端不支持 --by-directory 时直接回退，不再重试带开关的命令。
                    useServerDirectory = false
                    retryCount = 0
                    runQuery(context, server, groupingMode, useServerDirectory) { execId = it }
                } else if (retryCount < 3) {
                    // 重试时必须更新 execId，否则重试结果永远匹配不上监听器，页面会卡在加载态。
                    retryCount += 1
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        runQuery(context, server, groupingMode, useServerDirectory) { execId = it }
                    }, 1000)
                } else {
                    loading = false
                    errorMsg = event.data ?: "muxmirror 执行失败"
                }
            }
        }
        TermirrorCore.addEventListener(listener)
        runQuery(context, server, groupingMode, useServerDirectory) { id ->
            execId = id
            if (id <= 0) {
                loading = false
                errorMsg = "exec 通道创建失败"
            }
        }

        onDispose { TermirrorCore.removeEventListener(listener) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("导航") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            when {
                loading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(Modifier.height(8.dp))
                            Text("正在查询终端窗口...", fontSize = 14.sp)
                        }
                    }
                }
                errorMsg.isNotEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(errorMsg, color = MaterialTheme.colorScheme.error, fontSize = 14.sp)
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = { runQuery(context, server, groupingMode, useServerDirectory) { execId = it } }) { Text("重试") }
                        }
                    }
                }
                else -> {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(items) { item ->
                            DirectoryCard(
                                item = item,
                                onSelect = onSelect
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DirectoryCard(
    item: NavItem,
    onSelect: (String, String) -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable { onSelect(item.mux, item.session) },
                horizontalAlignment = Alignment.Start
            ) {
                Text(
                    item.title,
                    fontSize = 15.sp,
                    fontWeight = if (item.isActive) androidx.compose.ui.text.font.FontWeight.SemiBold else androidx.compose.ui.text.font.FontWeight.Normal
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (item.isActive) {
                        androidx.compose.foundation.Canvas(modifier = Modifier.size(6.dp)) {
                            drawCircle(color = androidx.compose.ui.graphics.Color(0xFF4CAF50))
                        }
                        Spacer(Modifier.width(6.dp))
                    }
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = MaterialTheme.shapes.small
                    ) {
                        Text(
                            "${item.mux}[${item.session}]",
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                            fontSize = 11.sp
                        )
                    }
                    Spacer(Modifier.width(6.dp))
                    Text(
                        item.subtitle,
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            if (item.tabs.size > 1) {
                Box {
                    TextButton(
                        onClick = { menuExpanded = true },
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text("${item.tabs.size} 个会话", fontSize = 12.sp)
                    }
                    DropdownMenu(
                        expanded = menuExpanded,
                        onDismissRequest = { menuExpanded = false },
                        modifier = Modifier.widthIn(min = 340.dp, max = 400.dp)
                    ) {
                        item.tabs.forEachIndexed { index, tab ->
                            DropdownMenuItem(
                                text = {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Surface(
                                            color = MaterialTheme.colorScheme.primaryContainer,
                                            shape = MaterialTheme.shapes.small
                                        ) {
                                            Text(
                                                "${tab.mux}[${tab.session}]",
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                                fontSize = 11.sp
                                            )
                                        }
                                        Spacer(Modifier.width(8.dp))
                                        Text(
                                            tab.title.ifBlank { tab.session },
                                            fontSize = 14.sp,
                                            fontWeight = if (tab.active) androidx.compose.ui.text.font.FontWeight.SemiBold else androidx.compose.ui.text.font.FontWeight.Normal
                                        )
                                    }
                                },
                                onClick = {
                                    menuExpanded = false
                                    onSelect(tab.mux, tab.session)
                                }
                            )
                            if (index < item.tabs.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(horizontal = 12.dp),
                                    color = MaterialTheme.colorScheme.outlineVariant
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

internal data class TabInfo(
    val title: String,
    val mux: String,
    val session: String,
    val active: Boolean,
    val cwd: String
)

internal data class NavItem(
    val title: String,
    val subtitle: String,
    val mux: String,
    val session: String,
    val isActive: Boolean,
    val tabs: List<TabInfo> = emptyList()
)

private fun runQuery(
    context: android.content.Context,
    server: ServerConfig,
    groupingMode: String,
    useServerDirectory: Boolean,
    setExecId: (Long) -> Unit
) {
    val cmd = if (groupingMode == SettingsStore.GROUPING_DIRECTORY && useServerDirectory) {
        "muxmirror -format json --mux --by-directory"
    } else {
        "muxmirror -format json --mux"
    }
    val id = TermirrorCore.execSession(server, cmd)
    setExecId(id)
}

internal fun parseMuxResult(raw: String, groupingMode: String, useServerDirectory: Boolean = false): List<NavItem> {
    val list = mutableListOf<NavItem>()
    val seenSessions = mutableSetOf<String>()
    try {
        val root = JSONObject(raw)
        val windows = root.optJSONArray("windows") ?: JSONArray()

        if (groupingMode == SettingsStore.GROUPING_WINDOW) {
            // 按窗口分组：每个窗口一个条目
            for (i in 0 until windows.length()) {
                val win = windows.getJSONObject(i)
                val tabsArr = win.optJSONArray("tabs") ?: JSONArray()
                val tabs = mutableListOf<TabInfo>()
                for (j in 0 until tabsArr.length()) {
                    val t = tabsArr.getJSONObject(j)
                    val session = t.optString("session", "").trim()
                    val mux = t.optString("mux", "").trim()
                    if (session.isEmpty() || mux.isEmpty()) continue
                    if (!seenSessions.add(muxSessionKey(mux, session))) continue
                    tabs.add(
                        TabInfo(
                            title = t.optString("title", "").ifBlank { session },
                            mux = mux,
                            session = session,
                            active = t.optBoolean("active", false),
                            cwd = t.optString("cwd", "")
                        )
                    )
                }
                if (tabs.isEmpty()) continue
                val activeTab = tabs.find { it.active }
                val representative = activeTab ?: tabs.first()
                list.add(
                    NavItem(
                        title = win.optString("title", "").ifBlank { representative.session },
                        subtitle = representative.session,
                        mux = representative.mux,
                        session = representative.session,
                        isActive = representative.active,
                        tabs = tabs
                    )
                )
            }
        } else {
            // 按工作目录（cwd）分组聚合所有 tmux/rmux 标签页
            val groups = mutableMapOf<String, MutableList<TabInfo>>()
            val groupTitles = mutableMapOf<String, String>()
            for (i in 0 until windows.length()) {
                val win = windows.getJSONObject(i)
                val tabsArr = win.optJSONArray("tabs") ?: JSONArray()
                val serverTitle = win.optString("title", "").trim()
                for (j in 0 until tabsArr.length()) {
                    val t = tabsArr.getJSONObject(j)
                    val session = t.optString("session", "").trim()
                    val mux = t.optString("mux", "").trim()
                    if (session.isEmpty() || mux.isEmpty()) continue
                    if (!seenSessions.add(muxSessionKey(mux, session))) continue
                    val cwd = t.optString("cwd", "").ifBlank {
                        t.optString("title", "").ifBlank { session }
                    }
                    val key = if (useServerDirectory && serverTitle.isNotEmpty()) {
                        serverTitle
                    } else {
                        cwd.ifBlank { session }
                    }
                    if (useServerDirectory && serverTitle.isNotEmpty()) {
                        groupTitles[key] = serverTitle
                    }
                    groups.getOrPut(key) { mutableListOf() }.add(
                        TabInfo(
                            title = t.optString("title", "").ifBlank { session },
                            mux = mux,
                            session = session,
                            active = t.optBoolean("active", false),
                            cwd = cwd
                        )
                    )
                }
            }

            for ((key, tabs) in groups) {
                val activeTab = tabs.find { it.active }
                val representative = activeTab ?: tabs.first()
                list.add(
                    NavItem(
                        title = groupTitles[key].orEmpty().ifBlank {
                            representative.cwd.ifBlank { representative.title }
                        },
                        subtitle = representative.session,
                        mux = representative.mux,
                        session = representative.session,
                        isActive = representative.active,
                        tabs = tabs
                    )
                )
            }
        }

        val detached = root.optJSONArray("detached") ?: JSONArray()
        for (i in 0 until detached.length()) {
            val d = detached.getJSONObject(i)
            val session = d.optString("session", "").trim()
            val mux = d.optString("mux", "").trim()
            if (session.isEmpty() || mux.isEmpty()) continue
            if (!seenSessions.add(muxSessionKey(mux, session))) continue
            list.add(
                NavItem(
                    title = session,
                    subtitle = d.optString("cwd", "").ifBlank { "未挂载" },
                    mux = mux,
                    session = session,
                    isActive = false
                )
            )
        }
    } catch (_: Exception) {
        // 解析失败返回空列表，上层显示错误。
    }
    return list
}

private fun muxSessionKey(mux: String, session: String): String {
    return "${mux.trim().uppercase()}:${session.trim()}"
}
