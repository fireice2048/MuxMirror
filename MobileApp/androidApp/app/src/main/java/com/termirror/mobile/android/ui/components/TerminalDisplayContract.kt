package com.termirror.mobile.android.ui.components

/**
 * 工具条按键标识，与鸿蒙 TERMINAL_TOOL_ROWS 对齐。
 */
enum class ToolbarKey {
    SLASH, MINUS, COLON, ASTERISK, PIPE,
    HOME, UP, END, PGUP, DEL,
    ESC, TAB, PAST, CTRL, ALT,
    LEFT, DOWN, RIGHT, PGDN, KBD
}

enum class TerminalMouseProtocol {
    NONE, X10, SGR;

    companion object {
        fun fromWire(value: String): TerminalMouseProtocol = when (value.lowercase()) {
            "x10" -> X10
            "sgr" -> SGR
            else -> NONE
        }
    }
}

enum class TerminalWheelDirection { UP, DOWN }

data class TerminalWheelBatch(
    val direction: TerminalWheelDirection,
    val steps: Int,
    val remainder: Float
)

/** 将连续手势位移量化为有限个滚轮刻度。正位移（手指向下拖）对应向上回看。 */
fun consumeTerminalWheelDelta(
    remainder: Float,
    deltaY: Float,
    threshold: Float = 28f,
    maxSteps: Int = 4
): TerminalWheelBatch {
    val safeThreshold = threshold.coerceAtLeast(1f)
    val total = remainder + deltaY
    return TerminalWheelBatch(
        direction = if (total >= 0) TerminalWheelDirection.UP else TerminalWheelDirection.DOWN,
        steps = (kotlin.math.abs(total) / safeThreshold).toInt().coerceIn(0, maxSteps.coerceAtLeast(0)),
        remainder = total % safeThreshold
    )
}

/** 编码 xterm 鼠标滚轮事件；坐标从 1 开始。 */
fun encodeTerminalWheel(
    protocol: TerminalMouseProtocol,
    direction: TerminalWheelDirection,
    column: Int,
    row: Int,
    repeat: Int = 1
): String {
    if (protocol == TerminalMouseProtocol.NONE) return ""
    val button = if (direction == TerminalWheelDirection.UP) 64 else 65
    val count = repeat.coerceIn(0, 16)
    if (protocol == TerminalMouseProtocol.SGR) {
        val col = column.coerceIn(1, 9999)
        val line = row.coerceIn(1, 9999)
        return "\u001B[<$button;$col;${line}M".repeat(count)
    }
    val col = column.coerceIn(1, 95)
    val line = row.coerceIn(1, 95)
    return "\u001B[M${(32 + button).toChar()}${(32 + col).toChar()}${(32 + line).toChar()}".repeat(count)
}

/**
 * 终端显示组件契约：页面层只依赖此接口，可随时替换渲染后端。
 */
interface TerminalDisplayController {
    fun handleToolKey(key: ToolbarKey)
    fun paste(text: String)
    fun focus()
    fun blur()
}

/**
 * 两行 10 键工具条数据定义。
 */
val TOOL_ROWS: List<List<Pair<ToolbarKey, String>>> = listOf(
    listOf(
        ToolbarKey.SLASH to "/",
        ToolbarKey.MINUS to "-",
        ToolbarKey.COLON to ":",
        ToolbarKey.ASTERISK to "*",
        ToolbarKey.PIPE to "|",
        ToolbarKey.HOME to "HOME",
        ToolbarKey.UP to "↑",
        ToolbarKey.END to "END",
        ToolbarKey.PGUP to "PGUP",
        ToolbarKey.DEL to "DEL"
    ),
    listOf(
        ToolbarKey.ESC to "ESC",
        ToolbarKey.TAB to "TAB",
        ToolbarKey.PAST to "PAST",
        ToolbarKey.CTRL to "CTRL",
        ToolbarKey.ALT to "ALT",
        ToolbarKey.LEFT to "←",
        ToolbarKey.DOWN to "↓",
        ToolbarKey.RIGHT to "→",
        ToolbarKey.PGDN to "PGDN",
        ToolbarKey.KBD to "⌨"
    )
)
