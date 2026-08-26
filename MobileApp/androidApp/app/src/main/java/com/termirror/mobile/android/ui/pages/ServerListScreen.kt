package com.termirror.mobile.android.ui.pages

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirror.mobile.android.R
import com.termirror.mobile.android.core.ServerConfig
import com.termirror.mobile.android.core.TermirrorCore
import com.termirror.mobile.android.ui.components.ServerEditDialog
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

@Composable
fun ServerListScreen(
    onOpenServer: (ServerConfig) -> Unit,
    onOpenNetworkDiag: () -> Unit,
    onOpenSettings: () -> Unit
) {
    var servers by remember { mutableStateOf(TermirrorCore.listConfigs()) }
    var editing by remember { mutableStateOf<ServerConfig?>(null) }
    var showAdd by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<ServerConfig?>(null) }
    var copying by remember { mutableStateOf<ServerConfig?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Image(
                            painter = painterResource(R.drawable.muxmirror_banner),
                            contentDescription = "MuxMirror",
                            modifier = Modifier.height(42.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("服务器列表", fontSize = 18.sp)
                    }
                },
                actions = {
                    IconButton(onClick = { showAdd = true }) {
                        Icon(Icons.Default.Add, contentDescription = "新增")
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
            ) {
                val listState = rememberLazyListState()
                val reorderState = rememberReorderableLazyListState(listState) { from, to ->
                    servers = servers.toMutableList().apply { add(to.index, removeAt(from.index)) }
                    TermirrorCore.moveConfig(from.index, to.index)
                }

                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(servers, key = { it.name }) { server ->
                        ReorderableItem(reorderState, key = server.name) { isDragging ->
                            val elevation = if (isDragging) 8.dp else 0.dp
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .longPressDraggableHandle()
                                    .clickable { onOpenServer(server) },
                                elevation = CardDefaults.cardElevation(defaultElevation = elevation)
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = server.name.ifBlank { server.host },
                                            fontSize = 16.sp,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        Text(
                                            text = "${server.username}@${server.host}:${server.port}",
                                            fontSize = 12.sp,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                    Row {
                                        IconButton(onClick = { editing = server }) {
                                            Icon(Icons.Default.Edit, contentDescription = "编辑", tint = MaterialTheme.colorScheme.primary)
                                        }
                                        IconButton(onClick = { copying = server }) {
                                            Icon(Icons.Default.ContentCopy, contentDescription = "复制", tint = MaterialTheme.colorScheme.primary)
                                        }
                                        IconButton(onClick = { deleting = server }) {
                                            Icon(Icons.Default.Delete, contentDescription = "删除", tint = MaterialTheme.colorScheme.error)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                TextButton(onClick = onOpenNetworkDiag) {
                    Text("网络诊断")
                }
            }

            SmallFloatingActionButton(
                onClick = onOpenSettings,
                modifier = Modifier.align(Alignment.BottomEnd),
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant
            ) {
                Icon(Icons.Default.Settings, contentDescription = "设置")
            }
        }
    }

    if (showAdd || editing != null) {
        val editingOriginal = editing
        ServerEditDialog(
            initial = editing,
            onDismiss = { showAdd = false; editing = null },
            onSave = { config ->
                // 编辑保存时若名称变更，先删除旧名称条目，避免 Rust 核心按 name upsert 造成重复。
                if (editingOriginal != null && editingOriginal.name != config.name) {
                    TermirrorCore.deleteConfig(editingOriginal.name)
                }
                TermirrorCore.saveConfig(config)
                servers = TermirrorCore.listConfigs()
                showAdd = false
                editing = null
            }
        )
    }

    copying?.let { server ->
        AlertDialog(
            onDismissRequest = { copying = null },
            title = { Text("复制服务器") },
            text = { Text("确定复制 ${server.name.ifBlank { server.host }} 吗？") },
            confirmButton = {
                TextButton(onClick = {
                    // 以“原名 副本”另存一条，名称冲突时追加序号。
                    var copyName = "${server.name} 副本"
                    var seq = 2
                    while (servers.any { it.name == copyName }) {
                        copyName = "${server.name} 副本$seq"
                        seq += 1
                    }
                    TermirrorCore.saveConfig(server.copy(name = copyName))
                    servers = TermirrorCore.listConfigs()
                    copying = null
                }) { Text("复制") }
            },
            dismissButton = {
                TextButton(onClick = { copying = null }) { Text("取消") }
            }
        )
    }

    deleting?.let { server ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("删除服务器") },
            text = { Text("确定删除 ${server.name} 吗？") },
            confirmButton = {
                TextButton(onClick = {
                    TermirrorCore.deleteConfig(server.name)
                    servers = TermirrorCore.listConfigs()
                    deleting = null
                }) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { deleting = null }) { Text("取消") }
            }
        )
    }
}
