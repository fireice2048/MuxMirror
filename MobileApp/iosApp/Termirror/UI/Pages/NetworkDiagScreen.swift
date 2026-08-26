import SwiftUI

private let terminalGreen = Color(red: 0.718, green: 0.969, blue: 0.757)
private let terminalBg = Color(red: 0.063, green: 0.075, blue: 0.094)
private let inputPlaceholder = "tcp <IP/域名> [端口]，例如：\ntcp 192.168.1.1 80\ntcp baidu.com 443"

struct NetworkDiagScreen: View {
    let onBack: () -> Void

    @State private var output = "网络诊断 已就绪。\n$ "
    @State private var input = ""
    @State private var subscription: TmEventSubscription?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(terminalGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(terminalBg)

            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $input)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(terminalGreen)
                        .scrollContentBackground(.hidden)
                        .background(terminalBg)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 72, maxHeight: 120)
                    if input.isEmpty {
                        Text(inputPlaceholder)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
                Button {
                    let command = input
                    input = ""
                    let result = runCommand(command) { host, port in
                        TermirrorCore.shared.tcpCheck(host: host, port: UInt16(port))
                    }
                    output += "\(command)\n\(result)"
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(primaryColor)
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("sendDiagButton")
            }
            .padding()
            .background(terminalBg)
        }
        .background(terminalBg)
        .navigationTitle("网络诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(terminalBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            subscription = TermirrorCore.shared.addEventHandler { event in
                if event.type == "diag" {
                    DispatchQueue.main.async {
                        output += "\(event.data ?? "")\n$ "
                    }
                }
            }
        }
        .onDisappear {
            if let sub = subscription { TermirrorCore.shared.removeEventHandler(sub) }
        }
    }
}

private let primaryColor = Color(red: 0.098, green: 0.529, blue: 0.333)

private func runCommand(_ command: String, onTcpCheck: (String, Int) -> Void) -> String {
    let parts = command.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map { String($0) }
    if parts.count < 2 || parts.count > 3 || parts[0].lowercased() != "tcp" {
        return "iOS 网络诊断仅支持 TCP 检测。\n用法：tcp <IP/域名> [端口]\n$ "
    }
    let host = parts[1]
    guard let port = Int(parts[safe: 2] ?? "443"), port >= 1 && port <= 65535 else {
        return "端口必须在 1 到 65535 之间\n$ "
    }
    onTcpCheck(host, port)
    return ""
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
