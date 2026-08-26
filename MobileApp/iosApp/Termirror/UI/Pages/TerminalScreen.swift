import SwiftUI
import Combine

struct TerminalScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    let server: ServerConfig
    let muxAttach: MuxAttach?
    let onBack: () -> Void
    let onOpenMuxNav: () -> Void

    @State private var phase = "connecting"
    @State private var errorText = ""
    @State private var sessionId: Int64 = -1
    @State private var controlLocked = false
    @State private var altLocked = false
    @State private var keyboardVisible = false
    @State private var keyboardRequestedVisible = false
    @State private var expandedMuxRows = 0
    @State private var snapshot = ""
    @State private var cursorOffset = 0
    @State private var styles: [TerminalStyleRange] = []
    @State private var mouseProtocol: TerminalMouseProtocol = .none
    @StateObject private var controller = TerminalTextController()
    @State private var subscription: TmEventSubscription?

    private let connectTimeoutMs: Double = 10000

    var body: some View {
        VStack(spacing: 0) {
            if phase == "connected" {
                VStack(spacing: 0) {
                    TerminalTextView(
                        controller: controller,
                        snapshot: snapshot,
                        cursorOffset: cursorOffset,
                        styles: styles,
                        mouseProtocol: mouseProtocol,
                        onInput: { data in
                            if sessionId > 0 { TermirrorCore.shared.writeSession(sessionId, data: data) }
                        },
                        onResize: { cols, rows in
                            guard sessionId > 0 else { return }
                            var targetRows = rows
                            if muxAttach != nil {
                                // 键盘弹出时 UIKit 可能先缩小终端视图，再回调键盘焦点；
                                // 保留键盘前的完整行数，避免 tmux 把底部输入区裁出快照。
                                let keyboardActive = keyboardVisible || keyboardRequestedVisible
                                if !keyboardActive {
                                    expandedMuxRows = rows
                                }
                                targetRows = effectiveMuxRows(
                                    muxAttached: true,
                                    rows: rows,
                                    keyboardVisible: keyboardVisible,
                                    keyboardRequestedVisible: keyboardRequestedVisible,
                                    expandedRows: expandedMuxRows
                                )
                            }
                            TermirrorCore.shared.resizeSession(
                                sessionId,
                                cols: UInt32(cols),
                                rows: UInt32(targetRows)
                            )
                        },
                        onKeyboardFocusChanged: { focused in
                            keyboardVisible = focused
                            if !focused { keyboardRequestedVisible = false }
                        }
                    )
                    .onAppear {
                        // 连接成功后使用已测得的尺寸同步 PTY
                        // TerminalTextView 会在 viewDidLayoutSubviews 中触发 onResize
                    }

                    TerminalToolbar(
                        controlLocked: $controlLocked,
                        altLocked: $altLocked,
                        onKeyAction: { key in
                            switch key {
                            case .ctrl:
                                controlLocked.toggle()
                            case .alt:
                                altLocked.toggle()
                            case .kbd:
                                if keyboardVisible {
                                    keyboardRequestedVisible = false
                                    controller.blur()
                                } else {
                                    keyboardRequestedVisible = true
                                    controller.focus()
                                }
                            case .past:
                                if let text = UIPasteboard.general.string {
                                    controller.paste(text)
                                }
                            default:
                                controller.handleToolKey(key)
                            }
                        }
                    )
                    .padding(.bottom, 8)
                    .background(
                        Color(red: 0.9, green: 0.957, blue: 0.918)
                            .ignoresSafeArea(.container, edges: .bottom)
                    )
                }
                .background(Color.black)
            } else {
                VStack(spacing: 12) {
                    if phase == "connecting" {
                        ProgressView()
                    }
                    Text(phase == "connecting" ? "Loading · 正在连接 \(server.host):\(server.port)" : errorText)
                    Button("返回服务器列表") { onBack() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .foregroundColor(.white)
            }
        }
        .navigationTitle(server.name.isEmpty ? server.host : server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // 已通过导航页 attach 到 mux 会话时，隐藏 MUX 入口，避免重复 attach
                if muxAttach == nil {
                    Button("MUX...") { onOpenMuxNav() }
                        .disabled(phase != "connected")
                }
            }
        }
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .onAppear { startSession() }
        .onDisappear {
            if let sub = subscription { TermirrorCore.shared.removeEventHandler(sub) }
            if sessionId > 0 { TermirrorCore.shared.closeSession(sessionId) }
        }
    }

    private func startSession() {
        let handler: TmEventHandler = { event in
            guard event.sessionId == sessionId else { return }
            DispatchQueue.main.async {
                switch event.type {
                case "connectionState":
                    switch event.state {
                    case "connecting":
                        phase = "connecting"
                        errorText = ""
                    case "connected":
                        phase = "connected"
                        // 从 MUX 导航页选中标签进入时，连接成功后立即 attach 到目标会话
                        if let attach = muxAttach {
                            attachToMux(sessionId: sessionId, mux: attach.mux, session: attach.session)
                        }
                    case "failed":
                        phase = "failed"
                        errorText = event.data ?? "SSH 连接失败"
                    case "closed":
                        phase = "failed"
                        errorText = "会话已关闭"
                    default: break
                    }
                case "error":
                    phase = "failed"
                    errorText = event.data ?? "未知错误"
                case "output":
                    snapshot = event.data ?? ""
                    cursorOffset = event.cursor ?? snapshot.utf16.count
                    styles = event.styles
                    mouseProtocol = TerminalMouseProtocol(wireValue: event.mouseProtocol)
                default: break
                }
            }
        }
        subscription = TermirrorCore.shared.addEventHandler(handler)

        phase = "connecting"
        errorText = ""
        sessionId = TermirrorCore.shared.connectSession(server, cols: 100, rows: 32)
        if sessionId <= 0 {
            phase = "failed"
            errorText = "会话创建失败"
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(connectTimeoutMs))) {
                if phase == "connecting" {
                    phase = "failed"
                    errorText = "连接超时"
                    TermirrorCore.shared.closeSession(sessionId)
                }
            }
        }
    }
}

struct MuxAttach: Hashable {
    let mux: String
    let session: String
}

/// 键盘弹出期间保持 MUX client 的完整行数，避免底部输入区被 PTY resize 裁掉。
func effectiveMuxRows(
    muxAttached: Bool,
    rows: Int,
    keyboardVisible: Bool,
    keyboardRequestedVisible: Bool,
    expandedRows: Int
) -> Int {
    guard muxAttached, keyboardVisible || keyboardRequestedVisible, expandedRows > 0 else {
        return rows
    }
    return max(rows, expandedRows)
}

/// 生成从交互式 shell 进入指定 MUX 会话的命令。
func buildMuxAttachCommand(mux: String, session: String) -> String {
    let prefix = mux.caseInsensitiveCompare("RMUX") == .orderedSame ? "rmux" : "tmux"
    let muxEnvironment = "${TMUX-}${RMUX_SESSION-}${RMUX-}"
    let target = "'\(session.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    let clientTty = "${SSH_TTY:-$(tty 2>/dev/null)}"
    // 共享 pane 内无法判断输入来自哪个 client，禁止无 -c 的 switch-client。
    // 页面必须为目标会话新建 SSH PTY；若生命周期异常导致仍在 MUX 内，则安全拒绝。
    // ignore-size 下共享 window 可能高于手机 PTY，MUX 默认展示顶部裁剪区。
    // attach 注册 client 后在约 2 秒内重复下移该 TTY 的可见区域，避免初始化阶段
    // 把第一次 refresh 覆盖掉；不改变共享 window 尺寸。
    return "if [ -n \"\(muxEnvironment)\" ]; then " +
        "printf '%s\\n' 'TermMirror: refusing MUX attach from inside an existing MUX session' >&2; " +
        "else " +
        "(client_tty=\"\(clientTty)\"; " +
        "for i in 1 2 3 4 5 6 7 8 9 10; do " +
        "client=$(\(prefix) list-clients -F '#{client_tty}' 2>/dev/null | " +
        "grep -F -x \"$client_tty\" | head -n 1); " +
        "if [ -n \"$client\" ]; then " +
        "\(prefix) refresh-client -t \"$client\" -D 999 >/dev/null 2>&1; " +
        "fi; sleep 0.2; done) & " +
        "exec \(prefix) attach-session -f ignore-size -t \(target); fi"
}

private func attachToMux(sessionId: Int64, mux: String, session: String) {
    TermirrorCore.shared.writeSession(sessionId, data: "\(buildMuxAttachCommand(mux: mux, session: session))\r")
}
