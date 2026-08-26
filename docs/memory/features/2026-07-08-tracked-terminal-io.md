# 功能记忆：普通被跟踪终端 I/O

## 背景

- `PCServer/attach` 之前已经实现 managed PTY 路径（spawn-pty / read-screen / send-input / resize / close）。
- 普通 `tracked` session 只能做元数据跟踪、列表、连接和生命周期管理，`read_screen` / `send_input` / `resize` 返回 `unsupported_operation`。
- `docs/requirements/pc-server-progress.md` 六大板块完成后，下一步建议实现普通被跟踪 OS 终端的真实画面/输入绑定，或进入 Mobile 端联调。

## 关键功能点

- `attach track` 在启动 daemon 前检测当前 stdin 的 TTY/PTS 路径，通过 `ATTACH_TTY_PATH` 环境变量传给 daemon。
- `TerminalSession` 新增 `tty_path` 字段，注册时携带该路径。
- 新增 `PCServer/attach/src/tracked_tty.rs` 模块，封装 TTY 打开、输入转发、窗口大小调整和 screen buffer。
- `ServiceState` 为 tracked session 维护 `tracked_ttys` 绑定表；`read_screen` / `send_input` / `resize` 优先尝试 tracked session 绑定。
- Unix 平台声明 `supports_tracked_terminal_io: true`，协议 capabilities 增加 `tracked_terminal_io`。

## 设计与实现

- 涉及模块：`main.rs`、`session.rs`、`service.rs`、`tracked_tty.rs`、`platform.rs`、`protocol.rs`。
- 核心流程：
  1. `attach track` 调用 `detect_tty_path()` 获取当前终端 TTY 路径。
  2. daemon 通过 `ATTACH_TTY_PATH` 继承路径，注册 session 时写入 `tty_path`。
  3. 服务在 `read_screen` / `send_input` / `resize` 时惰性创建 `TrackedTerminal` 绑定。
  4. 绑定失败时返回 `unsupported_operation`，不 panic。
- 重要约束：
  - 已存在 OS 终端的 PTY master 由终端模拟器持有，通过 pts slave 路径只能转发输入，无法可靠读取子进程输出。
  - 多个 slave 打开者同时读写同一个 pts 时行为未定义，因此画面同步在真实场景下受限。
  - 当前实现为"最佳努力"方案：输入转发在可访问 TTY 时可用；画面读取可能为空或仅包含 echo。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：44 个单元测试 + 3 个 managed PTY 集成测试 + 1 个 tracked terminal 集成测试全部通过。
- 命令：`cargo clippy -p attach --all-targets --all-features`
- 结果：无 warning。

## 后续注意事项

- 真实画面同步可能需要终端模拟器特定 API（macOS AppleScript、Linux D-Bus/插件）或 PTY 包装模式。
- 如果需要完整的 tracked terminal I/O，后续可考虑让 `attach track` 支持可选的 PTY 包装，将当前 shell 迁移到 Attach 管理的 PTY 中。
- 当前方案已能满足 Mobile 端联调时通过 `send-input` 向被跟踪终端发送命令的基础需求。
