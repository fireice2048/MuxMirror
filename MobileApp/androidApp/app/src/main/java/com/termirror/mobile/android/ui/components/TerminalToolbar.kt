package com.termirror.mobile.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val KeyNormalBg = Color(0xFFE6F4EA)
private val KeyActiveBg = Color(0xFF1F7A3D)
private val KeyNormalFg = Color(0xFF198754)
private val KeyActiveFg = Color.White

@Composable
fun TerminalToolbar(
    controlLocked: Boolean,
    altLocked: Boolean,
    modifier: Modifier = Modifier,
    onKeyAction: (ToolbarKey) -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 4.dp, vertical = 2.dp)
    ) {
        TOOL_ROWS.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                row.forEach { (key, label) ->
                    val isChecked = (key == ToolbarKey.CTRL && controlLocked) ||
                            (key == ToolbarKey.ALT && altLocked)
                    ToolbarKeyButton(
                        label = label,
                        isChecked = isChecked,
                        isModifier = key == ToolbarKey.CTRL || key == ToolbarKey.ALT,
                        modifier = Modifier.weight(1f),
                        onClick = { onKeyAction(key) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ToolbarKeyButton(
    label: String,
    isChecked: Boolean,
    isModifier: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Box(
        modifier = modifier
            .height(40.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(if (isChecked) KeyActiveBg else KeyNormalBg)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            fontSize = 13.sp,
            color = if (isChecked) KeyActiveFg else KeyNormalFg,
            textAlign = TextAlign.Center,
            maxLines = 1,
            textDecoration = if (isModifier && isChecked) TextDecoration.Underline else TextDecoration.None
        )
    }
}
