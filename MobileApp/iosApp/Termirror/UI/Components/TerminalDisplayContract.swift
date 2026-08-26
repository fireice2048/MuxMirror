import Foundation

/// 工具条按键标识，与鸿蒙 TERMINAL_TOOL_ROWS 对齐。
enum ToolbarKey: String, CaseIterable {
    case slash = "/"
    case minus = "-"
    case colon = ":"
    case asterisk = "*"
    case pipe = "|"
    case home = "HOME"
    case up = "UP"
    case end = "END"
    case pgup = "PGUP"
    case del = "DEL"
    case esc = "ESC"
    case tab = "TAB"
    case past = "PAST"
    case ctrl = "CTRL"
    case alt = "ALT"
    case left = "LEFT"
    case down = "DOWN"
    case right = "RIGHT"
    case pgdn = "PGDN"
    case kbd = "KBD"
}

enum TerminalMouseProtocol: String {
    case none
    case x10
    case sgr

    init(wireValue: String) {
        self = TerminalMouseProtocol(rawValue: wireValue.lowercased()) ?? .none
    }
}

enum TerminalWheelDirection {
    case up
    case down
}

struct TerminalWheelBatch {
    let direction: TerminalWheelDirection
    let steps: Int
    let remainder: CGFloat
}

/// 将连续手势位移量化为有限个滚轮刻度。正位移（手指向下拖）对应向上回看。
func consumeTerminalWheelDelta(
    remainder: CGFloat,
    deltaY: CGFloat,
    threshold: CGFloat = 28,
    maxSteps: Int = 4
) -> TerminalWheelBatch {
    let safeThreshold = max(1, threshold)
    let total = remainder + deltaY
    return TerminalWheelBatch(
        direction: total >= 0 ? .up : .down,
        steps: min(max(0, maxSteps), Int(abs(total) / safeThreshold)),
        remainder: total.truncatingRemainder(dividingBy: safeThreshold)
    )
}

/// 编码 xterm 鼠标滚轮事件；坐标从 1 开始。
func encodeTerminalWheel(
    protocol mouseProtocol: TerminalMouseProtocol,
    direction: TerminalWheelDirection,
    column: Int,
    row: Int,
    repeat count: Int = 1
) -> String {
    guard mouseProtocol != .none else { return "" }
    let button = direction == .up ? 64 : 65
    let repetitions = min(16, max(0, count))
    if mouseProtocol == .sgr {
        let col = min(9999, max(1, column))
        let line = min(9999, max(1, row))
        return String(repeating: "\u{001B}[<\(button);\(col);\(line)M", count: repetitions)
    }
    let col = min(95, max(1, column))
    let line = min(95, max(1, row))
    let event = "\u{001B}[M" + String(UnicodeScalar(32 + button)!)
        + String(UnicodeScalar(32 + col)!) + String(UnicodeScalar(32 + line)!)
    return String(repeating: event, count: repetitions)
}

/// 终端显示组件契约：页面层只依赖此协议，可随时替换渲染后端。
@MainActor
protocol TerminalDisplayController: AnyObject {
    func handleToolKey(_ key: ToolbarKey)
    func paste(_ text: String)
    func focus()
    func blur()
}

/// 两行 10 键工具条数据定义。
let toolRows: [[(ToolbarKey, String)]] = [
    [
        (.slash, "/"), (.minus, "-"), (.colon, ":"), (.asterisk, "*"), (.pipe, "|"),
        (.home, "HOME"), (.up, "↑"), (.end, "END"), (.pgup, "PGUP"), (.del, "DEL")
    ],
    [
        (.esc, "ESC"), (.tab, "TAB"), (.past, "PAST"), (.ctrl, "CTRL"), (.alt, "ALT"),
        (.left, "←"), (.down, "↓"), (.right, "→"), (.pgdn, "PGDN"), (.kbd, "⌨")
    ]
]
