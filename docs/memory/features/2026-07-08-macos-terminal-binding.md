# 功能记忆：macOS 终端绑定

## 背景

- 普通被跟踪终端（tracked session）的画面同步在 Linux 上受 PTY master 持有权限制，无法可靠读取子进程输出。
- macOS Terminal.app 和 iTerm2 提供 AppleScript 接口，可以获取标签页内容、发送文本、调整窗口大小、枚举标签页，是完成 tracked terminal 真实 I/O 的可行路径。

## 关键功能点

- `attach track` 在 macOS 上通过 `macos_terminal::detect_terminal_id()` 获取当前 Terminal.app / iTerm2 标签页或 session 标识。
- 标识通过 `ATTACH_MACOS_TERMINAL_ID` 环境变量传给 daemon，最终写入 `TerminalSession::terminal_id`。
- 新增 `PCServer/attach/src/macos_terminal.rs`，封装 AppleScript 调用和 Terminal.app / iTerm2 适配器。
- `ServiceState` 在 macOS 上维护 `macos_adapters`，对 tracked session 优先使用 AppleScript 适配器处理 `read_screen` / `send_input` / `resize`。
- `active_sessions` 在 macOS 上调用 `update_macos_tab_titles()`，通过 `list_tabs()` 更新 tracked session 的 `title` 和 `tab_hint`；Terminal.app 标签页移动后仍通过 TTY 匹配标题。
- Terminal.app 标签页关闭后，下一次 `read_screen` / `send_input` / `resize` 会返回内部 `tab_closed` 错误，服务端清理对应 session 和 adapter 绑定。
- `read_screen` 对 Terminal.app 和 iTerm2 启用 200ms 短期画面缓存，降低高频轮询时的 `osascript` 进程启动开销；`send_input` / `resize` 成功后失效缓存。

## 设计与实现

- 涉及模块：`main.rs`、`session.rs`、`service.rs`、`macos_terminal.rs`、`platform.rs`。
- 核心流程：
  1. `attach track` 检测 `TERM_PROGRAM` 并调用对应适配器的 `detect_current_id()`；Terminal.app 返回 `window-id:tab-index:tty`。
  2. daemon 启动时继承 `ATTACH_MACOS_TERMINAL_ID`。
  3. 服务收到 `read_screen` / `send_input` / `resize` 时，优先查找或创建 macOS adapter 绑定。
  4. adapter 操作前调用 `resolve_terminal_app_tab()` 校验 TTY；若标签页已移动则按 TTY 重定位，若已关闭则返回 `tab_closed`。
  5. `service.rs` 检测到 `tab_closed` 后调用 `close_macos_session()` 清理 session 和 adapter 绑定。
  6. `read_screen` 命中 200ms 缓存时直接返回，避免重复调用 `osascript`；`send_input` / `resize` 成功后清空缓存。
  7. adapter 生成 AppleScript 并通过 `osascript -e` 执行。
- 重要约束：
  - Terminal.app 没有 `write text` 命令；有 Accessibility 权限时 `send_input` 使用 `System Events` 发送真实按键，无权限时降级为 `do script "printf '%s' \"...\""`，语义是执行命令而非纯按键输入，会污染 shell 历史。
  - Terminal.app 标签页标识已扩展为 `window-id:tab-index:tty`，在标签页存活期间通过 TTY 重新定位，降低拖动标签页导致索引失效的问题。
  - 若标签页已关闭，操作会返回内部 `tab_closed` 错误，服务端清理对应 session。
  - iTerm2 的 `write text` 更接近真实用户输入，且 session unique id 本身稳定。
  - AppleScript 需要终端应用允许脚本控制；首次运行时可能弹出权限提示。
  - Terminal.app 真实按键需要 `System Events` 的 Accessibility 权限，当前在 CLI 侧做了权限检测与引导。
  - 画面同步基于轮询，内容可能滞后。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：60 个单元测试（含 macOS 高频压测） + 3 个 managed PTY 集成测试 + 1 个 tracked terminal 集成测试全部通过。
- 命令：`cargo clippy -p attach --all-targets --all-features`
- 结果：无 warning。

## 当前限制

- Terminal.app `send_input` 在有 Accessibility 权限时使用 `System Events` 真实按键；无权限时降级为 `do script "printf '%s' \"...\""`，语义是执行命令而非纯按键输入，会污染 shell 历史。CLI 会在无权限时打印引导日志。
- 画面同步基于 `read-screen` 轮询调用 `osascript`，内容可能滞后，且每次调用都有进程启动开销；已为 Terminal.app 和 iTerm2 增加 200ms 短期缓存，TTL 内不会重复启动 `osascript`。
- AppleScript 需要终端应用允许脚本控制；首次运行时可能弹出权限提示，Terminal.app 真实按键还需要 Accessibility 权限。
- `tty` 在标签页关闭后可能被系统回收复用，因此不能作为持久 ID；仅用于存活期内的重定位和关闭检测。
- 用户切换标签页后，基于启动时 `terminal_id` 的绑定仍指向原标签页；Mobile 端可通过 `list-tabs` / `switch-tab` 主动切换，但尚未在 UI 中闭环。
- 尚未验证更大规模（数百标签页）或极长时间（数小时）运行场景下的稳定性；当前压测为开发级冒烟。

## 后续待办

- [x] 支持 Mobile 端列出并切换可用标签页（已完成：新增 `list-tabs` / `switch-tab` 协议与 CLI）。
- [x] 将 Terminal.app 的 `send_input` 从 `do script` 改为 `System Events` 发送真实按键，并在无权限时降级并引导用户（已完成）。
- [x] 增加 AppleScript 权限检测与引导（已完成：CLI 侧已打印权限引导）。
- [x] Terminal.app 标签页标识增加 TTY 并支持关闭检测（已完成：标识格式 `window-id:tab-index:tty`，按 TTY 重定位，关闭后清理 session）。
- [x] 探索流式推送或缓存，降低 `read-screen` 轮询开销（已完成：新增 200ms 画面缓存，命中时直接返回，输入/resize 后失效）。
- [x] 补充长时间/高频场景压测（已完成：新增 `macos_terminal_high_frequency_operations_are_stable` 单元测试，50 次高频 read + 10 轮 send/read，验证 adapter 绑定与 session 清理）。
