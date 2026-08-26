package com.termirror.mobile.android.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.termirror.mobile.android.core.ServerConfig

@Composable
fun ServerEditDialog(
    initial: ServerConfig?,
    onDismiss: () -> Unit,
    onSave: (ServerConfig) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var host by remember { mutableStateOf(initial?.host ?: "") }
    var port by remember { mutableStateOf((initial?.port ?: 22).toString()) }
    var username by remember { mutableStateOf(initial?.username ?: "") }
    var password by remember { mutableStateOf(initial?.password ?: "") }
    var passwordVisible by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initial == null) "新增服务器" else "编辑服务器") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称") }, singleLine = true)
                OutlinedTextField(value = host, onValueChange = { host = it }, label = { Text("主机") }, singleLine = true)
                OutlinedTextField(value = port, onValueChange = { port = it }, label = { Text("端口") }, singleLine = true)
                OutlinedTextField(value = username, onValueChange = { username = it }, label = { Text("用户名") }, singleLine = true)
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("密码") },
                    singleLine = true,
                    visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                imageVector = if (passwordVisible) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                                contentDescription = if (passwordVisible) "隐藏密码" else "显示密码"
                            )
                        }
                    }
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val portNum = port.toIntOrNull() ?: 22
                    onSave(ServerConfig(name.trim(), host.trim(), portNum, username.trim(), password))
                }
            ) { Text("保存") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        }
    )
}
