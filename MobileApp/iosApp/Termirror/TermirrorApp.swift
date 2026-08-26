import SwiftUI

@main
struct TermirrorApp: App {
    init() {
        let filesDir: String
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("termirror-uitesting-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            filesDir = tempDir.path
        } else {
            filesDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        }
        TermirrorCore.shared.initialize(filesDir: filesDir)
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--terminal-uitesting") {
                TerminalUITestHarness()
            } else {
                ContentView()
            }
        }
    }
}

struct ContentView: View {
    @State private var path = NavigationPath()
    @State private var selectedServer: ServerConfig?

    var body: some View {
        NavigationStack(path: $path) {
            ServerListScreen(
                onOpenServer: { server in
                    selectedServer = server
                    path.append(Route.terminal(server: server))
                },
                onOpenNetworkDiag: {
                    path.append(Route.networkDiag)
                }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .terminal(let server, let muxAttach):
                    TerminalScreen(
                        server: server,
                        muxAttach: muxAttach,
                        onBack: { path.removeLast() },
                        onOpenMuxNav: { path.append(Route.muxNav(server: server)) }
                    )
                case .muxNav(let server):
                    MuxNavScreen(
                        server: server,
                        onSelect: { mux, session in
                            // 选中标签后在导航页之上压入新的终端页（携带 attach 目标），
                            // 返回键先回到导航页，再退到进入导航前的终端页，不会直接回首页。
                            path.append(Route.terminal(server: server, muxAttach: MuxAttach(mux: mux, session: session)))
                        },
                        onBack: { path.removeLast() }
                    )
                case .networkDiag:
                    NetworkDiagScreen(onBack: { path.removeLast() })
                }
            }
        }
    }
}

enum Route: Hashable {
    case terminal(server: ServerConfig, muxAttach: MuxAttach? = nil)
    case muxNav(server: ServerConfig)
    case networkDiag
}
