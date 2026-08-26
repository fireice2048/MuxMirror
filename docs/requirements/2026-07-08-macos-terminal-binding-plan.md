# macOS 终端绑定实现计划

## 背景

- 服务端已支持 managed PTY 的完整 I/O（spawn-pty / read-screen / send-input / resize / close）。
- Unix 上已通过 TTY/PTS 路径为普通 tracked session 提供基础输入转发，但画面同步受 PTY master 持有权限制，无法可靠读取子进程输出。
- macOS 上 Terminal.app 和 iTerm2 均提供 AppleScript 接口，可获取窗口/标签页内容、发送文本、调整窗口大小、枚举标签页，是完成 tracked terminal 画面同步与标签页识别的可行路径。

## 目标

在 macOS 上为 Terminal.app 和 iTerm2 实现 tracked session 的画面同步、输入转发、窗口大小调整和标签页识别。

## 技术方案

1. **终端检测与标识**
   - `attach track` 执行时通过 `TERM_PROGRAM` 识别当前终端程序（`Apple_Terminal` 或 `iTerm.app`）。
   - 通过 AppleScript 获取当前窗口/标签页/session 的标识（索引或 ID），通过环境变量 `ATTACH_MACOS_TERMINAL_ID` 传给 daemon。
   - `TerminalSession::from_environment()` 读取该标识并写入 `tab_hint` 或新增 `terminal_id` 字段。

2. **AppleScript 桥接层**
   - 新增 `PCServer/attach/src/macos_terminal.rs` 模块，封装 `osascript` 调用。
   - 提供统一 trait `MacosTerminalAdapter`：
     - `read_screen(terminal_id) -> Result<String>`
     - `send_input(terminal_id, input) -> Result<()>`
     - `resize(terminal_id, cols, rows) -> Result<()>`
     - `list_tabs() -> Result<Vec<TabInfo>>`
   - 分别实现 `TerminalAppAdapter` 和 `Iterm2Adapter`。

3. **服务层接入**
   - `ServiceState` 在 macOS 上维护 `macos_adapters: BTreeMap<String, Box<dyn MacosTerminalAdapter>>`（或按 terminal_id 缓存）。
   - `read_screen` / `send_input` / `resize` 对 tracked session 优先尝试 macOS adapter；失败时降级到 `tracked_tty` 或 `unsupported_operation`。

4. **标签页识别**
   - 心跳或 `list_sessions` 时，如果当前终端是 Terminal.app/iTerm2，通过 AppleScript 获取真实标签页标题并更新 `tab_hint` / `title`。

5. **平台能力声明**
   - macOS adapter limitations 移除 `tracked_terminal_io_requires_tty_access` 等旧限制，改为声明 Accessibility 权限需求。
   - 当 Terminal.app 或 iTerm2 可用时，`supports_tracked_terminal_io` 保持 `true`。

## 任务拆分

1. 新增 `PCServer/attach/src/macos_terminal.rs`，定义 adapter trait 和 Terminal.app 实现。
2. 实现 iTerm2 adapter。
3. `session.rs` 新增 `terminal_id: Option<String>` 字段，支持 `ATTACH_MACOS_TERMINAL_ID`。
4. `main.rs` 在 `attach track` 中检测 macOS 终端并获取 terminal_id。
5. `service.rs` 接入 macOS adapter，优先级高于 `tracked_tty`。
6. 在心跳或列表时更新标签页标题。
7. 更新 `platform.rs` 能力声明。
8. 添加单元测试（mock osascript 输出）和集成测试（在真实 macOS 终端环境中运行，可选）。
9. 更新 `README.md`、验收文档、memory。

## 风险与约束

- **权限**：通过 `System Events` 发送按键需要 Accessibility 权限；直接调用 Terminal.app/iTerm2 脚本通常不需要。
- **性能**：每次 `read-screen` 调用 `osascript` 有进程启动开销，高频轮询可能卡顿；后续可考虑缓存或流式推送。
- **多标签页**：用户切换标签页后，基于启动时 terminal_id 的绑定可能指向原标签页。需要设计更新机制或允许 Mobile 端选择标签页。
- **安全性**：AppleScript 可以控制其他应用，需确保只在用户明确启动 `attach track` 的终端上执行。

## 验收标准

- macOS 上 `attach track` 后，`attach read-screen <session-id>` 能返回当前 Terminal.app 或 iTerm2 标签页的文本内容。
- `attach send-input <session-id> "..."` 能将文本写入对应终端。
- `attach resize <session-id> <cols> <rows>` 能调整对应终端窗口大小。
- `attach list` 中 tracked session 的 `title` / `tab_hint` 反映真实标签页信息。
- `cargo test -p attach` 通过；`cargo clippy` 无新增 warning。
