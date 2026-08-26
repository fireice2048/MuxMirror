import SwiftUI
import Combine

// 与电脑端 macOS Terminal 的 Clear Dark profile 对齐。ANSI 24 位真彩色
// 仍由远端原样提供；仅默认色和 Rust 通用 16 色表在 iOS 侧映射到该 profile。
private let terminalBg = Color(red: 0.129, green: 0.153, blue: 0.200)
private let terminalGreen = Color(red: 0.898, green: 0.898, blue: 0.898)
private let terminalDim = Color(red: 0.494, green: 0.518, blue: 0.545)

private let clearDarkAnsiPalette: [String: String] = [
    "#000000": "#35424B",
    "#CD3131": "#B35547",
    "#0DAC59": "#6CAA70",
    "#E5E510": "#C4AB62",
    "#2473C8": "#6D95B3",
    "#BC3FBC": "#BD7BCC",
    "#11A8CD": "#7BCACD",
    "#E5E5E5": "#DDE5EB",
    "#666666": "#465C6C",
    "#F14C4C": "#DF6C59",
    "#23D18B": "#78BD7D",
    "#F5F543": "#E5C871",
    "#3B8EEA": "#66B5EC",
    "#D670D6": "#D389E5",
    "#29B8DB": "#84DDE0",
    "#FFFFFF": "#E5EEF5"
]

/// 默认 iOS 终端显示后端：SwiftUI Text + AttributedString 渲染快照，
/// 隐藏 TextField 接收系统软键盘输入。符合 TerminalDisplayController 协议，
/// 可随时替换为 SwiftTerm 或其他原生终端控件。
struct TerminalTextView: UIViewControllerRepresentable {
    @ObservedObject var controller: TerminalTextController
    let snapshot: String
    let cursorOffset: Int
    let styles: [TerminalStyleRange]
    let mouseProtocol: TerminalMouseProtocol
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void
    let onKeyboardFocusChanged: (Bool) -> Void

    func makeUIViewController(context: Context) -> TerminalTextViewController {
        let vc = TerminalTextViewController()
        vc.onInput = onInput
        vc.onResize = onResize
        vc.onKeyboardFocusChanged = onKeyboardFocusChanged
        vc.mouseProtocol = mouseProtocol
        controller.viewController = vc
        controller.onInput = onInput
        return vc
    }

    func updateUIViewController(_ uiViewController: TerminalTextViewController, context: Context) {
        uiViewController.update(snapshot: snapshot, cursorOffset: cursorOffset, styles: styles)
        uiViewController.mouseProtocol = mouseProtocol
    }
}

/// 命令式控制器，供 TerminalPage 调用。
@MainActor
final class TerminalTextController: TerminalDisplayController, ObservableObject {
    weak var viewController: TerminalTextViewController?

    func handleToolKey(_ key: ToolbarKey) {
        switch key {
        case .slash: onInput?("/")
        case .minus: onInput?("-")
        case .colon: onInput?(":")
        case .asterisk: onInput?("*")
        case .pipe: onInput?("|")
        case .pgup: viewController?.pageScroll(.up)
        case .pgdn: viewController?.pageScroll(.down)
        case .home, .up, .end, .del, .esc, .tab, .left, .down, .right:
            onInput?(TermirrorCore.shared.encodeKey(key.rawValue, ctrl: false, alt: false))
        default: break
        }
    }

    func paste(_ text: String) {
        onInput?(text)
    }

    func focus() {
        viewController?.focus()
    }

    func blur() {
        viewController?.blur()
    }

    var onInput: ((String) -> Void)?
}

/// UIKit 容器：UITextView 显示快照 + 隐藏 UITextField 接收键盘。
final class TerminalTextViewController: UIViewController {
    var onInput: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    var onKeyboardFocusChanged: ((Bool) -> Void)?
    var mouseProtocol: TerminalMouseProtocol = .none

    private let textView = UITextView()
    private let hiddenInput = UITextField()
    private var pendingKeyboardFocus = false
    private var lastSize = CGSize.zero
    private var lastCols = 100
    private var lastRows = 32
    private var remoteWheelRemainder: CGFloat = 0

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(terminalBg)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = UIColor(terminalGreen)
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        // 单指由 UITextView 本地滚动；双指专用于远端 TUI 滚轮。
        textView.panGestureRecognizer.maximumNumberOfTouches = 1
        textView.accessibilityIdentifier = "terminalTextView"

        hiddenInput.translatesAutoresizingMaskIntoConstraints = false
        hiddenInput.alpha = 0.01
        hiddenInput.autocapitalizationType = .none
        hiddenInput.autocorrectionType = .no
        hiddenInput.spellCheckingType = .no
        hiddenInput.keyboardType = .asciiCapable
        hiddenInput.returnKeyType = .send
        hiddenInput.accessibilityIdentifier = "terminalInputField"
        hiddenInput.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        hiddenInput.delegate = self
        hiddenInput.text = "\u{200B}"

        let tap = UITapGestureRecognizer(target: self, action: #selector(focusFromTap))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)

        let remotePan = UIPanGestureRecognizer(target: self, action: #selector(handleRemotePan(_:)))
        remotePan.minimumNumberOfTouches = 2
        remotePan.maximumNumberOfTouches = 2
        remotePan.cancelsTouchesInView = false
        remotePan.delegate = self
        textView.addGestureRecognizer(remotePan)

        view.addSubview(textView)
        view.addSubview(hiddenInput)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            hiddenInput.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hiddenInput.topAnchor.constraint(equalTo: view.topAnchor),
            hiddenInput.widthAnchor.constraint(equalToConstant: 2),
            hiddenInput.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard textView.bounds.size != lastSize else { return }
        lastSize = textView.bounds.size
        let charWidth = "M".size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width
        let lineHeight = textView.font?.lineHeight ?? 16
        // TextKit 的 CJK 回退字体可能略宽于拉丁 M，预留两列避免系统软换行。
        let cols = max(20, Int((textView.bounds.width - 24) / charWidth) - 2)
        let rows = max(5, Int((textView.bounds.height - 24) / lineHeight))
        lastCols = cols
        lastRows = rows
        onResize?(cols, rows)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if pendingKeyboardFocus {
            focus()
        } else {
            // 控制器本身接收外接键盘，不主动弹出屏幕软键盘。
            becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key, handleHardwareKey(key) else {
                unhandled.insert(press)
                continue
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    func update(snapshot: String, cursorOffset: Int, styles: [TerminalStyleRange]) {
        let attr = buildAttributedSnapshot(snapshot: snapshot, styles: styles, cursorOffset: cursorOffset, cursorVisible: true)
        let wasNearBottom = textView.contentOffset.y + textView.bounds.height >= textView.contentSize.height - 24
        textView.attributedText = attr
        textView.accessibilityValue = snapshot
        textView.layoutIfNeeded()
        if wasNearBottom || textView.contentOffset.y == 0 {
            let bottom = max(-textView.adjustedContentInset.top, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
            textView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        }
    }

    func focus() {
        pendingKeyboardFocus = true
        guard viewIfLoaded?.window != nil else { return }
        resignFirstResponder()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingKeyboardFocus = !self.hiddenInput.becomeFirstResponder()
        }
    }

    func blur() {
        pendingKeyboardFocus = false
        hiddenInput.resignFirstResponder()
        becomeFirstResponder()
    }

    func pageScroll(_ direction: TerminalWheelDirection) {
        if mouseProtocol != .none {
            let data = encodeTerminalWheel(
                protocol: mouseProtocol,
                direction: direction,
                column: max(1, lastCols / 2),
                row: max(1, lastRows / 2),
                repeat: 8
            )
            if !data.isEmpty { onInput?(data) }
            return
        }
        let minimum = -textView.adjustedContentInset.top
        let maximum = max(minimum, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
        let delta = direction == .up ? -textView.bounds.height : textView.bounds.height
        textView.setContentOffset(
            CGPoint(x: textView.contentOffset.x, y: min(maximum, max(minimum, textView.contentOffset.y + delta))),
            animated: true
        )
    }

    @objc private func handleRemotePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            remoteWheelRemainder = 0
            gesture.setTranslation(.zero, in: textView)
        case .changed:
            let deltaY = gesture.translation(in: textView).y
            gesture.setTranslation(.zero, in: textView)
            guard mouseProtocol != .none else { return }
            let batch = consumeTerminalWheelDelta(remainder: remoteWheelRemainder, deltaY: deltaY)
            remoteWheelRemainder = batch.remainder
            guard batch.steps > 0 else { return }
            let data = encodeTerminalWheel(
                protocol: mouseProtocol,
                direction: batch.direction,
                column: max(1, lastCols / 2),
                row: max(1, lastRows / 2),
                repeat: batch.steps
            )
            if !data.isEmpty { onInput?(data) }
        default:
            remoteWheelRemainder = 0
        }
    }

    @objc private func focusFromTap() {
        focus()
    }

    @objc private func editingChanged() {
        hiddenInput.text = "\u{200B}"
    }

    private func handleHardwareKey(_ key: UIKey) -> Bool {
        if key.modifierFlags.contains(.command) {
            return false
        }

        let ctrl = key.modifierFlags.contains(.control)
        let alt = key.modifierFlags.contains(.alternate)
        if !ctrl && !alt && key.keyCode == .keyboardPageUp {
            pageScroll(.up)
            return true
        }
        if !ctrl && !alt && key.keyCode == .keyboardPageDown {
            pageScroll(.down)
            return true
        }
        let namedKey: String? = switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: "ENTER"
        case .keyboardDeleteOrBackspace: "BACKSPACE"
        case .keyboardDeleteForward: "DEL"
        case .keyboardEscape: "ESC"
        case .keyboardTab: "TAB"
        case .keyboardHome: "HOME"
        case .keyboardEnd: "END"
        case .keyboardPageUp: "PGUP"
        case .keyboardPageDown: "PGDN"
        case .keyboardUpArrow: "UP"
        case .keyboardDownArrow: "DOWN"
        case .keyboardLeftArrow: "LEFT"
        case .keyboardRightArrow: "RIGHT"
        case .keyboardF1: "F1"
        case .keyboardF2: "F2"
        case .keyboardF3: "F3"
        case .keyboardF4: "F4"
        case .keyboardF5: "F5"
        case .keyboardF6: "F6"
        case .keyboardF7: "F7"
        case .keyboardF8: "F8"
        case .keyboardF9: "F9"
        case .keyboardF10: "F10"
        case .keyboardF11: "F11"
        case .keyboardF12: "F12"
        default: nil
        }

        if let namedKey {
            onInput?(TermirrorCore.shared.encodeKey(namedKey, ctrl: ctrl, alt: alt))
            return true
        }

        let text = (ctrl || alt) ? key.charactersIgnoringModifiers : key.characters
        guard !text.isEmpty else {
            return false
        }
        onInput?(ctrl || alt
            ? TermirrorCore.shared.encodeKey(text, ctrl: ctrl, alt: alt)
            : text)
        return true
    }
}

extension TerminalTextViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension TerminalTextViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        pendingKeyboardFocus = false
        onKeyboardFocusChanged?(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onKeyboardFocusChanged?(false)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty && range.length > 0 {
            onInput?(TermirrorCore.shared.encodeKey("BACKSPACE", ctrl: false, alt: false))
        } else {
            onInput?(string)
        }
        textField.text = "\u{200B}"
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onInput?("\r")
        return false
    }
}

private func buildAttributedSnapshot(snapshot: String, styles: [TerminalStyleRange], cursorOffset: Int, cursorVisible: Bool) -> NSAttributedString {
    let attr = NSMutableAttributedString(string: snapshot)
    let fullRange = NSRange(location: 0, length: snapshot.utf16.count)
    attr.addAttribute(.foregroundColor, value: UIColor(terminalGreen), range: fullRange)
    attr.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: fullRange)

    for style in styles {
        let start = max(0, min(style.start, snapshot.utf16.count))
        let end = max(start, min(style.end, snapshot.utf16.count))
        if start >= end { continue }
        let range = NSRange(location: start, length: end - start)
        let fg = style.foreground.flatMap(resolvedTerminalColor)
            ?? (style.style == "dim" ? UIColor(terminalDim) : UIColor(terminalGreen))
        let bg = style.background.flatMap(resolvedTerminalColor)
        if style.style == "inverse" {
            attr.addAttribute(.foregroundColor, value: bg ?? UIColor(terminalBg), range: range)
            attr.addAttribute(.backgroundColor, value: fg, range: range)
        } else {
            attr.addAttribute(.foregroundColor, value: fg, range: range)
            if let bg = bg {
                attr.addAttribute(.backgroundColor, value: bg, range: range)
            }
        }
    }

    let cursor = max(0, min(cursorOffset, snapshot.utf16.count))
    if cursorVisible && cursor < snapshot.utf16.count {
        let ch = snapshot.utf16[snapshot.utf16.index(snapshot.utf16.startIndex, offsetBy: cursor)]
        if ch != 10 {
            let range = NSRange(location: cursor, length: 1)
            attr.addAttribute(.foregroundColor, value: UIColor(terminalBg), range: range)
            attr.addAttribute(.backgroundColor, value: UIColor(terminalGreen), range: range)
        } else {
            attr.append(NSAttributedString(string: "▌", attributes: [
                .foregroundColor: UIColor(terminalGreen)
            ]))
        }
    } else if cursorVisible {
        attr.append(NSAttributedString(string: "▌", attributes: [
            .foregroundColor: UIColor(terminalGreen)
        ]))
    }

    return attr
}

private func resolvedTerminalColor(_ hex: String) -> UIColor? {
    UIColor(hex: clearDarkAnsiPalette[hex.uppercased()] ?? hex)
}

extension UIColor {
    convenience init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch trimmed.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }
}

#if DEBUG
/// 终端控件的确定性 UI 验收页，不依赖 SSH 服务或账号状态。
struct TerminalUITestHarness: View {
    @StateObject private var controller = TerminalTextController()
    @State private var keyboardFocused = false
    @State private var controlLocked = false
    @State private var altLocked = false

    private let sample = """
    MuxMirror ANSI rendering
    红色 绿色 蓝色  中文宽字符对齐
    0123456789 | abcdefghijklmnopqrstuvwxyz
    INVERSE  DIM  cursor>
    """

    private var sampleStyles: [TerminalStyleRange] {
        let ns = sample as NSString
        func range(_ text: String, foreground: String? = nil, background: String? = nil, style: String = "normal") -> TerminalStyleRange {
            let value = ns.range(of: text)
            return TerminalStyleRange(
                start: value.location,
                end: value.location + value.length,
                style: style,
                foreground: foreground,
                background: background
            )
        }
        return [
            range("ANSI", foreground: "#FFD75F"),
            range("红色", foreground: "#FF5F5F"),
            range("绿色", foreground: "#5FFF87"),
            range("蓝色", foreground: "#5F87FF"),
            range("INVERSE", foreground: "#FFFFFF", background: "#00875F", style: "inverse"),
            range("DIM", foreground: "#A0A0A0", style: "dim")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalTextView(
                controller: controller,
                snapshot: sample,
                cursorOffset: sample.utf16.count,
                styles: sampleStyles,
                mouseProtocol: .none,
                onInput: { _ in },
                onResize: { _, _ in },
                onKeyboardFocusChanged: { keyboardFocused = $0 }
            )
            TerminalToolbar(
                controlLocked: $controlLocked,
                altLocked: $altLocked,
                onKeyAction: { key in
                    if key == .kbd {
                        keyboardFocused ? controller.blur() : controller.focus()
                    }
                }
            )
        }
        .background(Color.black)
    }
}
#endif
