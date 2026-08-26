import Foundation

/// Rust → UI 事件，与 libtermirror_core 契约一致。
struct TmEvent {
    let sessionId: Int64
    let type: String
    let state: String?
    let data: String?
    let cursor: Int?
    let styles: [TerminalStyleRange]
    let mouseProtocol: String
}

/// 终端样式区间。
struct TerminalStyleRange {
    let start: Int
    let end: Int
    let style: String
    let foreground: String?
    let background: String?
}

/// 服务器配置，与 tmConfigList / tmConfigSave 的 JSON 结构一致。
struct ServerConfig: Codable, Equatable, Hashable {
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String

    enum CodingKeys: String, CodingKey {
        case name, host, port, username, password
    }
}

/// 回调类型。
typealias TmEventHandler = (TmEvent) -> Void

/// 事件订阅令牌，用于取消监听。
final class TmEventSubscription {
    let handler: TmEventHandler
    init(_ handler: @escaping TmEventHandler) { self.handler = handler }
}

/// Rust 核心 C ABI 的 Swift 封装（薄层）。
/// Android 走 JNI，iOS 直接 C 互操作，接口语义保持一致。
final class TermirrorCore: @unchecked Sendable {
    static let shared = TermirrorCore()
    private init() {}

    private var handlers: [TmEventSubscription] = []
    private let lock = NSLock()
    private var initialized = false

    func initialize(filesDir: String) {
        guard !initialized else { return }
        initialized = true
        tm_init(filesDir)
        let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { cJson in
            guard let cJson = cJson else { return }
            let json = String(cString: cJson)
            TermirrorCore.shared.dispatch(json)
        }
        tm_on_event(callback)
    }

    func addEventHandler(_ handler: @escaping TmEventHandler) -> TmEventSubscription {
        let sub = TmEventSubscription(handler)
        lock.lock()
        handlers.append(sub)
        lock.unlock()
        return sub
    }

    func removeEventHandler(_ subscription: TmEventSubscription) {
        lock.lock()
        handlers.removeAll { $0 === subscription }
        lock.unlock()
    }

    private func dispatch(_ json: String) {
        let event = parseEvent(json)
        lock.lock()
        let copy = handlers
        lock.unlock()
        DispatchQueue.main.async {
            copy.forEach { $0.handler(event) }
        }
    }

    private func parseEvent(_ json: String) -> TmEvent {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TmEvent(sessionId: 0, type: "error", state: nil, data: json, cursor: nil, styles: [], mouseProtocol: "none")
        }
        let sessionId = (dict["sessionId"] as? NSNumber)?.int64Value ?? 0
        let type = dict["type"] as? String ?? ""
        let state = dict["state"] as? String
        let dataStr = dict["data"] as? String
        let cursor = (dict["cursor"] as? NSNumber)?.intValue
        let mouseProtocol = dict["mouseProtocol"] as? String ?? "none"
        let styles = (dict["styles"] as? [[String: Any]] ?? []).compactMap { raw -> TerminalStyleRange? in
            guard let start = (raw["start"] as? NSNumber)?.intValue,
                  let end = (raw["end"] as? NSNumber)?.intValue,
                  let style = raw["style"] as? String else {
                return nil
            }
            return TerminalStyleRange(
                start: start,
                end: end,
                style: style,
                foreground: raw["foreground"] as? String,
                background: raw["background"] as? String
            )
        }
        return TmEvent(
            sessionId: sessionId,
            type: type,
            state: state,
            data: dataStr,
            cursor: cursor,
            styles: styles,
            mouseProtocol: mouseProtocol
        )
    }

    // MARK: - Session API

    func connectSession(_ config: ServerConfig, cols: UInt32, rows: UInt32) -> Int64 {
        let params = encodeConfig(config, cols: cols, rows: rows)
        return tm_session_connect(params)
    }

    func writeSession(_ sessionId: Int64, data: String) {
        tm_session_write(sessionId, data)
    }

    func resizeSession(_ sessionId: Int64, cols: UInt32, rows: UInt32) {
        tm_session_resize(sessionId, cols, rows)
    }

    func execSession(_ config: ServerConfig, command: String) -> Int64 {
        let params = encodeConfig(config)
        return tm_session_exec(params, command)
    }

    func closeSession(_ sessionId: Int64) {
        tm_session_close(sessionId)
    }

    func encodeKey(_ key: String, ctrl: Bool, alt: Bool) -> String {
        let ptr = tm_encode_key(key, ctrl, alt)
        defer { tm_string_free(ptr) }
        return ptr.flatMap { String(cString: $0, encoding: .utf8) } ?? ""
    }

    // MARK: - Config API

    func listConfigs() -> [ServerConfig] {
        let ptr = tm_config_list()
        defer { tm_string_free(ptr) }
        guard let ptr = ptr,
              let cString = String(cString: ptr, encoding: .utf8),
              let data = cString.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([ServerConfig].self, from: data)
        } catch {
            print("Parse config list failed: \(error)")
            return []
        }
    }

    func saveConfig(_ config: ServerConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        tm_config_save(json)
    }

    func deleteConfig(name: String) {
        tm_config_delete(name)
    }

    func moveConfig(from: UInt32, to: UInt32) -> Bool {
        return tm_config_move(from, to)
    }

    // MARK: - Diagnostics

    func tcpCheck(host: String, port: UInt16) {
        tm_tcp_check(host, port)
    }

    // MARK: - Helpers

    private func encodeConfig(_ config: ServerConfig, cols: UInt32? = nil, rows: UInt32? = nil) -> String {
        var dict: [String: Any] = [
            "host": config.host,
            "port": config.port,
            "username": config.username,
            "password": config.password
        ]
        if let cols = cols { dict["cols"] = cols }
        if let rows = rows { dict["rows"] = rows }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
