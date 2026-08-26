import SwiftUI

struct ServerListScreen: View {
    let onOpenServer: (ServerConfig) -> Void
    let onOpenNetworkDiag: () -> Void

    @State private var servers: [ServerConfig] = []
    @State private var editing: ServerConfig?
    @State private var showAdd = false
    @State private var deleting: ServerConfig?
    @State private var showDeleteAlert = false
    @State private var copySource: ServerConfig?
    @State private var showCopyAlert = false
    @State private var showSettings = false

    /// 主题色（与鸿蒙版 `ohos_id_color_primary` 对齐的深绿色）。
    private let primaryColor = Color(red: 0.098, green: 0.529, blue: 0.333)

    var body: some View {
        serverListContent
            .overlay(alignment: .bottomTrailing) { settingsButton }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .onAppear { reload() }
            .onChange(of: showAdd) { isPresented in
                if !isPresented { reload() }
            }
            .onChange(of: editing) { item in
                if item == nil { reload() }
            }
            .sheet(item: $editing) { server in
                ServerEditSheet(config: server) { newConfig in
                    saveConfigHandlingRename(old: server, new: newConfig)
                    reload()
                    editing = nil
                }
            }
            .sheet(isPresented: $showAdd) {
                ServerEditSheet(config: nil) { newConfig in
                    TermirrorCore.shared.saveConfig(newConfig)
                    reload()
                    showAdd = false
                }
            }
            .alert("删除服务器", isPresented: $showDeleteAlert) {
                Button("删除", role: .destructive) {
                    if let server = deleting {
                        TermirrorCore.shared.deleteConfig(name: server.name)
                        reload()
                    }
                    deleting = nil
                }
                Button("取消", role: .cancel) {
                    deleting = nil
                }
            } message: {
                if let server = deleting {
                    Text("确定删除 \(server.displayName) 吗？")
                }
            }
    }

    private var serverListContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
            networkDiagButton
        }
        .alert("复制服务器", isPresented: $showCopyAlert) {
            Button("复制") {
                if let server = copySource {
                    copyServer(server)
                }
                copySource = nil
            }
            Button("取消", role: .cancel) {
                copySource = nil
            }
        } message: {
            if let server = copySource {
                Text("将从「\(server.displayName)」生成一份新的服务器数据")
            }
        }
    }

    /// 顶部 banner + 标题 + 加号按钮。
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Image("Banner")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .accessibilityLabel("MuxMirror")
                Text("服务器列表")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showAdd = true }) {
                ZStack {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 42, height: 42)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .accessibilityIdentifier("addServerButton")
            .accessibilityLabel("新增服务器")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// 服务器列表。
    private var list: some View {
        List {
            ForEach($servers) { $server in
                ServerRow(server: server) {
                    onOpenServer(server)
                } edit: {
                    editing = server
                } copy: {
                    copySource = server
                    showCopyAlert = true
                } delete: {
                    deleting = server
                    showDeleteAlert = true
                }
            }
            .onMove { from, to in
                servers.move(fromOffsets: from, toOffset: to)
                guard let source = from.first else { return }
                if !TermirrorCore.shared.moveConfig(from: UInt32(source), to: UInt32(to)) {
                    reload()
                }
            }
        }
        .listStyle(.plain)
    }

    /// 底部网络诊断入口。
    private var networkDiagButton: some View {
        Button("网络诊断") { onOpenNetworkDiag() }
            .font(.callout)
            .foregroundColor(primaryColor)
            .padding()
    }

    /// 右下角设置入口。
    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gear")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(primaryColor)
                .clipShape(Circle())
        }
        .padding()
        .accessibilityIdentifier("settingsButton")
        .accessibilityLabel("设置")
    }

    private func reload() {
        servers = TermirrorCore.shared.listConfigs()
    }

    /// 编辑保存时若名称变更，先删除旧名称条目，避免 Rust 核心按 name upsert 造成重复。
    private func saveConfigHandlingRename(old: ServerConfig, new: ServerConfig) {
        if old.name != new.name {
            TermirrorCore.shared.deleteConfig(name: old.name)
        }
        TermirrorCore.shared.saveConfig(new)
    }

    /// 复制服务器：以“原名 副本”另存一条，名称冲突时追加序号。
    private func copyServer(_ server: ServerConfig) {
        var copyName = "\(server.name) 副本"
        var seq = 2
        while servers.contains(where: { $0.name == copyName }) {
            copyName = "\(server.name) 副本\(seq)"
            seq += 1
        }
        var copy = server
        copy.name = copyName
        TermirrorCore.shared.saveConfig(copy)
        reload()
    }
}

private struct ServerRow: View {
    let server: ServerConfig
    let open: () -> Void
    let edit: () -> Void
    let copy: () -> Void
    let delete: () -> Void

    private let primaryColor = Color(red: 0.098, green: 0.529, blue: 0.333)

    var body: some View {
        HStack {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.displayName)
                        .font(.headline)
                    Text("\(server.username)@\(server.host):\(String(server.port))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 16) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .foregroundColor(primaryColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editButton_\(server.name)")
                .accessibilityLabel("编辑 \(server.displayName)")
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(primaryColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("copyButton_\(server.name)")
                .accessibilityLabel("复制 \(server.displayName)")
                Button(action: delete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("deleteButton_\(server.name)")
                .accessibilityLabel("删除 \(server.displayName)")
            }
        }
        .padding(.vertical, 4)
    }
}

struct ServerEditSheet: View {
    let config: ServerConfig?
    let onSave: (ServerConfig) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private let primaryColor = Color(red: 0.098, green: 0.529, blue: 0.333)

    private enum Field {
        case name, host, port, username, password
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("nameTextField")
                TextField("主机", text: $host)
                    .focused($focusedField, equals: .host)
                    .accessibilityIdentifier("hostTextField")
                TextField("端口", text: $port)
                    .focused($focusedField, equals: .port)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("portTextField")
                TextField("用户名", text: $username)
                    .focused($focusedField, equals: .username)
                    .accessibilityIdentifier("usernameTextField")
                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("密码", text: $password)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("密码", text: $password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityIdentifier("togglePasswordVisibilityButton")
                    .accessibilityLabel(isPasswordVisible ? "隐藏密码" : "显示密码")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("passwordFieldRow")
            }
            .navigationTitle(config == nil ? "新增服务器" : "编辑服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .accessibilityIdentifier("saveServerButton")
                }
            }
        }
        .onAppear {
            if let c = config {
                name = c.name
                host = c.host
                port = String(c.port)
                username = c.username
                password = c.password
            } else {
                port = "22"
            }
            DispatchQueue.main.async {
                focusedField = .name
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let portNum = Int(port) ?? 22
        onSave(ServerConfig(
            name: trimmedName,
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNum,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        ))
    }
}

extension ServerConfig: Identifiable {
    /// 以 name 作为唯一标识，与 Rust 核心按 name upsert/delete 的契约一致。
    var id: String { name }

    /// 展示名称：名称为空时回退到主机地址。
    var displayName: String { name.isEmpty ? host : name }
}

// MARK: - 设置页面

struct SettingsScreen: View {
    @AppStorage("muxGroupingMode") private var groupingMode: String = "window"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("标签页分组方式") {
                    Picker("", selection: $groupingMode) {
                        Text("按窗口分组").tag("window")
                        Text("按目录分组").tag("directory")
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
