package com.termirror.mobile.android.ui.components

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.termirror.mobile.android.core.TerminalStyleRange
import com.termirror.mobile.android.core.TermirrorCore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max

private val TerminalBg = Color(0xFF101318)
/** 默认前景色：贴近电脑终端的浅灰（用户要求与 PC 端观感一致，不再使用品牌浅绿）。 */
private val TerminalFg = Color(0xFFE0E0E0)
private val TerminalDim = Color(0xFF7F7F7F)

/**
 * 默认 Android 终端显示后端：用 Jetpack Compose Text + AnnotatedString 渲染快照，
 * 隐藏 BasicTextField 接收系统软键盘输入。符合 TerminalDisplayController 契约，
 * 可随时替换为其他原生终端控件（如基于 Canvas 或第三方终端库）。
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun TerminalComposeView(
    controller: TerminalComposeController,
    snapshot: String,
    cursorOffset: Int,
    styles: List<TerminalStyleRange>,
    mouseProtocol: TerminalMouseProtocol,
    onInput: (String) -> Unit,
    onResize: (Int, Int) -> Unit,
    modifier: Modifier = Modifier,
    onFocusChanged: (Boolean) -> Unit = {}
) {
    val scrollState = rememberScrollState()
    val coroutineScope = rememberCoroutineScope()
    val hardwareFocusRequester = remember { FocusRequester() }
    val imeFocusRequester = remember { FocusRequester() }

    var imeValue by remember { mutableStateOf(TextFieldValue("")) }
    var cursorVisible by remember { mutableStateOf(true) }
    var lastCols by remember { mutableIntStateOf(100) }
    var lastRows by remember { mutableIntStateOf(32) }

    val pageScroll: (TerminalWheelDirection) -> Unit = { direction ->
        if (mouseProtocol != TerminalMouseProtocol.NONE) {
            onInput(encodeTerminalWheel(mouseProtocol, direction, lastCols / 2, lastRows / 2, 8))
        } else {
            val distance = scrollState.viewportSize.coerceAtLeast(1)
            val target = scrollState.value + if (direction == TerminalWheelDirection.UP) -distance else distance
            coroutineScope.launch { scrollState.animateScrollTo(target.coerceIn(0, scrollState.maxValue)) }
        }
    }

    // 光标闪烁
    LaunchedEffect(Unit) {
        while (true) {
            delay(500)
            cursorVisible = !cursorVisible
        }
    }

    // 连接建立后自动滚底
    LaunchedEffect(snapshot) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current

    // 注入控制器回调，供 TerminalScreen 命令式调用
    DisposableEffect(controller, onInput, pageScroll, hardwareFocusRequester, imeFocusRequester) {
        controller.onInput = onInput
        controller.pageScroll = pageScroll
        controller.focus = { imeFocusRequester.requestFocus() }
        controller.blur = {
            focusManager.clearFocus(force = true)
            hardwareFocusRequester.requestFocus()
        }
        onDispose { }
    }

    // 默认只聚焦硬件按键接收层，不主动弹出屏幕软键盘。
    LaunchedEffect(hardwareFocusRequester) {
        hardwareFocusRequester.requestFocus()
    }

    val density = LocalDensity.current
    val TERMINAL_PADDING_HORIZONTAL = 12f
    val TERMINAL_PADDING_TOP = 8f
    val TERMINAL_FONT_SIZE = 14f
    val TERMINAL_LINE_HEIGHT = 20f
    val PTY_COL_SAFETY = 2

    Box(modifier = modifier
        .fillMaxSize()
        .focusRequester(hardwareFocusRequester)
        .focusable()
        .onPreviewKeyEvent { event -> handleHardwareKeyEvent(event, onInput, pageScroll) }
        // 点击终端区域聚焦隐藏输入框，弹起软键盘（与 iOS/鸿蒙行为一致）
        .clickable(
            interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() },
            indication = null
        ) { imeFocusRequester.requestFocus() }
        .onSizeChanged { size ->
            val paddingHorizontalPx = with(density) { TERMINAL_PADDING_HORIZONTAL.dp.toPx() }
            val paddingTopPx = with(density) { TERMINAL_PADDING_TOP.dp.toPx() }
            val charWidthPx = with(density) { TERMINAL_FONT_SIZE.dp.toPx() } * 0.58f
            val lineHeightPx = with(density) { TERMINAL_LINE_HEIGHT.dp.toPx() }
            val availWidth = (size.width - paddingHorizontalPx * 2).coerceAtLeast(0f)
            val availHeight = (size.height - paddingTopPx).coerceAtLeast(0f)
            val cols = max(20, (availWidth / charWidthPx).toInt() - PTY_COL_SAFETY)
            val rows = max(5, (availHeight / lineHeightPx).toInt())
            lastCols = cols
            lastRows = rows
            onResize(cols, rows)
        }) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(TerminalBg)
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .pointerInput(mouseProtocol, lastCols, lastRows) {
                    awaitEachGesture {
                        var lastCentroidY: Float? = null
                        var wheelRemainder = 0f
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val pressed = event.changes.filter { it.pressed }
                            if (pressed.isEmpty()) break
                            if (pressed.size >= 2) {
                                val centroidY = pressed.take(2).sumOf { it.position.y.toDouble() }.toFloat() / 2f
                                lastCentroidY?.let { previousY ->
                                    if (mouseProtocol != TerminalMouseProtocol.NONE) {
                                        val batch = consumeTerminalWheelDelta(wheelRemainder, centroidY - previousY)
                                        wheelRemainder = batch.remainder
                                        if (batch.steps > 0) {
                                            onInput(encodeTerminalWheel(
                                                mouseProtocol,
                                                batch.direction,
                                                (lastCols / 2).coerceAtLeast(1),
                                                (lastRows / 2).coerceAtLeast(1),
                                                batch.steps
                                            ))
                                        }
                                    }
                                }
                                lastCentroidY = centroidY
                                pressed.forEach { it.consume() }
                            } else {
                                lastCentroidY = null
                                wheelRemainder = 0f
                            }
                        }
                    }
                }
                .verticalScroll(scrollState)
        ) {
            Text(
                text = buildAnnotatedSnapshot(snapshot, styles, cursorOffset, cursorVisible),
                style = TextStyle(
                    color = TerminalFg,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                )
            )
        }

        // 隐藏输入框：仅用于接收软键盘文本；大小写 / 自动校正等关闭，避免命令被改。
        BasicTextField(
            value = imeValue,
            onValueChange = { value ->
                val inserted = value.text
                val previous = imeValue.text
                if (inserted.length > previous.length) {
                    val text = inserted.substring(previous.length)
                    onInput(text)
                } else if (inserted.length < previous.length) {
                    onInput(TermirrorCore.encodeKey("BACKSPACE", false, false))
                }
                imeValue = TextFieldValue("")
            },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Ascii,
                imeAction = ImeAction.Send,
                capitalization = KeyboardCapitalization.None,
                autoCorrect = false
            ),
            modifier = Modifier
                .size(1.dp)
                .alpha(0.01f)
                .focusRequester(imeFocusRequester)
                .onFocusChanged { onFocusChanged(it.isFocused) },
            textStyle = TextStyle(color = Color.Transparent)
        )
    }
}

private fun handleHardwareKeyEvent(
    event: androidx.compose.ui.input.key.KeyEvent,
    onInput: (String) -> Unit,
    pageScroll: (TerminalWheelDirection) -> Unit
): Boolean {
    if (event.type != KeyEventType.KeyDown) return false
    val nativeEvent = event.nativeKeyEvent ?: return false
    if (nativeEvent.isMetaPressed) return false

    val ctrl = nativeEvent.isCtrlPressed
    val alt = nativeEvent.isAltPressed
    if (!ctrl && !alt && nativeEvent.keyCode == KeyEvent.KEYCODE_PAGE_UP) {
        pageScroll(TerminalWheelDirection.UP)
        return true
    }
    if (!ctrl && !alt && nativeEvent.keyCode == KeyEvent.KEYCODE_PAGE_DOWN) {
        pageScroll(TerminalWheelDirection.DOWN)
        return true
    }
    val namedKey = when (nativeEvent.keyCode) {
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> "ENTER"
        KeyEvent.KEYCODE_DEL -> "BACKSPACE"
        KeyEvent.KEYCODE_FORWARD_DEL -> "DEL"
        KeyEvent.KEYCODE_ESCAPE -> "ESC"
        KeyEvent.KEYCODE_TAB -> "TAB"
        KeyEvent.KEYCODE_MOVE_HOME -> "HOME"
        KeyEvent.KEYCODE_MOVE_END -> "END"
        KeyEvent.KEYCODE_PAGE_UP -> "PGUP"
        KeyEvent.KEYCODE_PAGE_DOWN -> "PGDN"
        KeyEvent.KEYCODE_DPAD_UP -> "UP"
        KeyEvent.KEYCODE_DPAD_DOWN -> "DOWN"
        KeyEvent.KEYCODE_DPAD_LEFT -> "LEFT"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "RIGHT"
        KeyEvent.KEYCODE_F1 -> "F1"
        KeyEvent.KEYCODE_F2 -> "F2"
        KeyEvent.KEYCODE_F3 -> "F3"
        KeyEvent.KEYCODE_F4 -> "F4"
        KeyEvent.KEYCODE_F5 -> "F5"
        KeyEvent.KEYCODE_F6 -> "F6"
        KeyEvent.KEYCODE_F7 -> "F7"
        KeyEvent.KEYCODE_F8 -> "F8"
        KeyEvent.KEYCODE_F9 -> "F9"
        KeyEvent.KEYCODE_F10 -> "F10"
        KeyEvent.KEYCODE_F11 -> "F11"
        KeyEvent.KEYCODE_F12 -> "F12"
        else -> null
    }
    if (namedKey != null) {
        onInput(TermirrorCore.encodeKey(namedKey, ctrl, alt))
        return true
    }

    val characterMetaState = if (ctrl || alt) {
        nativeEvent.metaState and
                (KeyEvent.META_CTRL_MASK or KeyEvent.META_ALT_MASK or KeyEvent.META_META_MASK).inv()
    } else {
        nativeEvent.metaState
    }
    val unicode = nativeEvent.getUnicodeChar(characterMetaState)
    if (unicode == 0) return false

    val text = String(Character.toChars(unicode))
    onInput(if (ctrl || alt) TermirrorCore.encodeKey(text, ctrl, alt) else text)
    return true
}

private fun buildAnnotatedSnapshot(
    snapshot: String,
    styles: List<TerminalStyleRange>,
    cursorOffset: Int,
    cursorVisible: Boolean
): AnnotatedString {
    return buildAnnotatedString {
        if (styles.isEmpty()) {
            append(snapshot)
        } else {
            var position = 0
            styles.sortedBy { it.start }.forEach { range ->
                if (range.start > position) {
                    append(snapshot.substring(position, range.start.coerceAtMost(snapshot.length)))
                }
                val end = range.end.coerceAtMost(snapshot.length)
                val start = range.start.coerceAtLeast(position).coerceAtMost(end)
                if (start < end) {
                    val fg = range.foreground?.let { Color(android.graphics.Color.parseColor(it)) }
                        ?: if (range.style == "dim") TerminalDim else TerminalFg
                    val bg = range.background?.let { Color(android.graphics.Color.parseColor(it)) }
                    val spanStyle = when (range.style) {
                        "inverse" -> SpanStyle(
                            color = bg ?: TerminalBg,
                            background = fg
                        )
                        "bold" -> SpanStyle(
                            color = fg,
                            background = bg ?: Color.Transparent,
                            fontWeight = FontWeight.Bold
                        )
                        else -> SpanStyle(
                            color = fg,
                            background = bg ?: Color.Transparent
                        )
                    }
                    pushStyle(spanStyle)
                    append(snapshot.substring(start, end))
                    pop()
                }
                position = end
            }
            if (position < snapshot.length) {
                append(snapshot.substring(position))
            }
        }

        // 覆盖式光标：在 cursorOffset 处插入闪烁块
        val cursor = cursorOffset.coerceIn(0, snapshot.length)
        if (cursorVisible && cursor < snapshot.length) {
            val ch = snapshot[cursor]
            if (ch != '\n') {
                addStyle(
                    SpanStyle(color = TerminalBg, background = TerminalFg),
                    cursor,
                    cursor + 1
                )
            } else {
                addStyle(
                    SpanStyle(color = TerminalFg),
                    cursor,
                    cursor
                )
                append("▌")
            }
        } else if (cursorVisible) {
            append("▌")
        }
    }
}

/**
 * Compose 终端渲染后端的命令式控制器实现。
 */
class TerminalComposeController : TerminalDisplayController {
    var onInput: (String) -> Unit = {}
    var pageScroll: (TerminalWheelDirection) -> Unit = {}
    var focus: () -> Unit = {}
    var blur: () -> Unit = {}

    override fun handleToolKey(key: ToolbarKey) {
        when (key) {
            ToolbarKey.SLASH -> onInput("/")
            ToolbarKey.MINUS -> onInput("-")
            ToolbarKey.COLON -> onInput(":")
            ToolbarKey.ASTERISK -> onInput("*")
            ToolbarKey.PIPE -> onInput("|")
            ToolbarKey.HOME -> onInput(TermirrorCore.encodeKey("HOME", false, false))
            ToolbarKey.UP -> onInput(TermirrorCore.encodeKey("UP", false, false))
            ToolbarKey.END -> onInput(TermirrorCore.encodeKey("END", false, false))
            ToolbarKey.PGUP -> pageScroll(TerminalWheelDirection.UP)
            ToolbarKey.DEL -> onInput(TermirrorCore.encodeKey("DEL", false, false))
            ToolbarKey.ESC -> onInput(TermirrorCore.encodeKey("ESC", false, false))
            ToolbarKey.TAB -> onInput(TermirrorCore.encodeKey("TAB", false, false))
            ToolbarKey.LEFT -> onInput(TermirrorCore.encodeKey("LEFT", false, false))
            ToolbarKey.DOWN -> onInput(TermirrorCore.encodeKey("DOWN", false, false))
            ToolbarKey.RIGHT -> onInput(TermirrorCore.encodeKey("RIGHT", false, false))
            ToolbarKey.PGDN -> pageScroll(TerminalWheelDirection.DOWN)
            else -> {}
        }
    }

    override fun paste(text: String) {
        onInput(text)
    }

    override fun focus() {
        focus.invoke()
    }

    override fun blur() {
        blur.invoke()
    }
}
