import SwiftUI

struct NavTab: Codable {
    let title: String
    let active: Bool
    let mux: String
    let session: String
    let cwd: String
}

struct NavWindow: Codable {
    let title: String
    let id: Int
    let tabs: [NavTab]
}

struct NavDetached: Codable {
    let mux: String
    let session: String
    let cwd: String
}

struct MuxList: Codable {
    let windows: [NavWindow]
    let detached: [NavDetached]
}

struct NavItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let mux: String
    let session: String
    let tabs: [NavTab]
    let isActive: Bool
}

struct MuxNavScreen: View {
    let server: ServerConfig
    let onSelect: (String, String) -> Void
    let onBack: () -> Void

    @State private var loading = true
    @State private var errorMsg = ""
    @State private var items: [NavItem] = []
    @State private var retryCount = 0
    @State private var execId: Int64 = -1
    @State private var subscription: TmEventSubscription?
    @AppStorage("muxGroupingMode") private var groupingMode: String = "window"
    @State private var useServerDirectory = false

    var body: some View {
        Group {
            if loading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在查询终端窗口...")
                        .foregroundColor(.secondary)
                }
            } else if !errorMsg.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMsg).foregroundColor(.red)
                    Button("重试") { runQuery() }
                }
            } else {
                List(items) { item in
                    DirectoryRow(item: item, onSelect: onSelect)
                }
            }
        }
        .navigationTitle("导航")
        .onAppear {
            useServerDirectory = groupingMode == "directory"
            subscription = TermirrorCore.shared.addEventHandler { event in
                guard event.type == "execResult", event.sessionId == self.execId else { return }
                if event.state == "ok" {
                    self.handleResult(event.data ?? "")
                } else if self.groupingMode == "directory" && self.useServerDirectory {
                    self.useServerDirectory = false
                    self.retryCount = 0
                    self.runQuery()
                } else {
                    self.scheduleRetry(reason: event.data ?? "muxmirror 执行失败")
                }
            }
            runQuery()
        }
        .onDisappear {
            if let sub = subscription { TermirrorCore.shared.removeEventHandler(sub) }
        }
    }

    private func runQuery() {
        loading = true
        errorMsg = ""
        items = []
        let flag = groupingMode == "directory" && useServerDirectory ? " --by-directory" : ""
        execId = TermirrorCore.shared.execSession(server, command: "muxmirror -format json --mux\(flag)")
        if execId <= 0 {
            loading = false
            errorMsg = "exec 通道创建失败"
        }
    }

    private func scheduleRetry(reason: String) {
        if retryCount < 3 {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                runQuery()
            }
        } else {
            loading = false
            errorMsg = reason
        }
    }
}

struct DirectoryRow: View {
    let item: NavItem
    let onSelect: (String, String) -> Void
    @State private var sessionPickerPresented = false

    var body: some View {
        Button(action: { onSelect(item.mux, item.session) }) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .fontWeight(item.isActive ? .semibold : .regular)
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        if item.isActive {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }
                        Text("\(item.mux)[\(item.session)]")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                            .foregroundColor(.primary)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if item.tabs.count > 1 {
                    Button(action: { sessionPickerPresented = true }) {
                        Text("\(item.tabs.count) 个会话")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .popover(
                        isPresented: $sessionPickerPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .trailing
                    ) {
                        SessionPicker(
                            tabs: item.tabs,
                            onSelect: { tab in
                                sessionPickerPresented = false
                                onSelect(tab.mux, tab.session)
                            }
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SessionPicker: View {
    let tabs: [NavTab]
    let onSelect: (NavTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.session) { index, tab in
                Button(action: { onSelect(tab) }) {
                    HStack(spacing: 10) {
                        Text("\(tab.mux)[\(tab.session)]")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(5)
                            .foregroundColor(.primary)
                        Text(tab.title.isEmpty ? tab.session : tab.title)
                            .font(.subheadline)
                            .fontWeight(tab.active ? .semibold : .regular)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < tabs.count - 1 {
                    Divider()
                        .padding(.horizontal, 14)
                }
            }
        }
        .frame(width: 340)
        .padding(.vertical, 4)
        .presentationCompactAdaptationCompat()
    }
}

private extension View {
    @ViewBuilder
    func presentationCompactAdaptationCompat() -> some View {
        if #available(iOS 16.4, *) {
            presentationCompactAdaptation(.popover)
        } else {
            self
        }
    }
}

extension MuxNavScreen {
    func handleResult(_ raw: String) {
        guard let result = parseMuxResult(raw, groupingMode: groupingMode, useServerDirectory: useServerDirectory) else {
            if groupingMode == "directory" && useServerDirectory {
                useServerDirectory = false
                retryCount = 0
                runQuery()
            } else {
                scheduleRetry(reason: "muxmirror 输出解析失败")
            }
            return
        }

        items = result
        loading = false
        errorMsg = result.isEmpty ? "没有终端窗口" : ""
    }
}

/// 解析服务端 MUX JSON，并按 mux + session 去重。
/// `useServerDirectory` 为 true 时，优先使用 --by-directory 返回的窗口标题作为目录组标题。
func parseMuxResult(_ raw: String, groupingMode: String, useServerDirectory: Bool = false) -> [NavItem]? {
    guard let data = raw.data(using: .utf8),
          let list = try? JSONDecoder().decode(MuxList.self, from: data) else {
        return nil
    }

    var result: [NavItem] = []
    var seenSessions = Set<String>()

    if groupingMode == "window" {
        for win in list.windows {
            let tabs = win.tabs.filter { tab in
                let session = tab.session.trimmingCharacters(in: .whitespacesAndNewlines)
                let mux = tab.mux.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !session.isEmpty, !mux.isEmpty else { return false }
                return seenSessions.insert(muxSessionKey(mux, session)).inserted
            }
            if tabs.isEmpty { continue }
            let activeTab = tabs.first { $0.active }
            let representative = activeTab ?? tabs[0]
            result.append(NavItem(
                title: win.title.isEmpty ? representative.session : win.title,
                subtitle: representative.session,
                mux: representative.mux,
                session: representative.session,
                tabs: tabs,
                isActive: representative.active
            ))
        }
    } else {
        // 按工作目录（cwd）分组聚合所有 tmux/rmux 标签页。
        var groups: [String: [NavTab]] = [:]
        var groupTitles: [String: String] = [:]
        for win in list.windows {
            let serverTitle = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
            for tab in win.tabs {
                let session = tab.session.trimmingCharacters(in: .whitespacesAndNewlines)
                let mux = tab.mux.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !session.isEmpty, !mux.isEmpty else { continue }
                guard seenSessions.insert(muxSessionKey(mux, session)).inserted else { continue }
                let cwd = tab.cwd.isEmpty ? (tab.title.isEmpty ? session : tab.title) : tab.cwd
                let key = useServerDirectory && !serverTitle.isEmpty ? serverTitle : (cwd.isEmpty ? session : cwd)
                if useServerDirectory && !serverTitle.isEmpty {
                    groupTitles[key] = serverTitle
                }
                groups[key, default: []].append(tab)
            }
        }

        for key in groups.keys.sorted() {
            guard let tabs = groups[key], let representative = tabs.first(where: { $0.active }) ?? tabs.first else { continue }
            let title = groupTitles[key] ?? (representative.cwd.isEmpty ? representative.title : representative.cwd)
            result.append(NavItem(
                title: title,
                subtitle: representative.session,
                mux: representative.mux,
                session: representative.session,
                tabs: tabs,
                isActive: representative.active
            ))
        }
    }

    for detached in list.detached {
        let session = detached.session.trimmingCharacters(in: .whitespacesAndNewlines)
        let mux = detached.mux.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty, !mux.isEmpty else { continue }
        guard seenSessions.insert(muxSessionKey(mux, session)).inserted else { continue }
        result.append(NavItem(
            title: session,
            subtitle: detached.cwd.isEmpty ? "未挂载" : detached.cwd,
            mux: mux,
            session: session,
            tabs: [],
            isActive: false
        ))
    }

    return result
}

private func muxSessionKey(_ mux: String, _ session: String) -> String {
    "\(mux.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()):\(session.trimmingCharacters(in: .whitespacesAndNewlines))"
}

// 事件监听由上层页面持有，这里仅提供结果处理方法。
// 在真实项目中应通过 ObservableObject 或 Environment 统一处理。
