# PC 服务端 Mobile API 草案

## 目标

Mobile 端通过 SSH 登录电脑后，可执行 `attach auth-info` 获取本机服务 endpoint 和 token，再通过 TCP JSON line 协议访问 Attach 服务。

Mobile 端集成详细协议见 `docs/requirements/mobile-attach-protocol.md`，包含 SSH 后鉴权、窗口/标签页查询、终端数据流读取、按键发送和完整交互示例。

## 传输

- 编码：每个请求和响应均为一行 JSON，以 `\n` 结束。
- 鉴权：请求外层必须包含 `token` 和 `request`。
- 服务发现：`attach auth-info` 输出 `endpoint`、`token`、`user`、`protocol_version`。

## 基础请求

- `hello`：返回 `protocol_version` 和 `capabilities`。
- `status`：返回 `protocol_version`、`platform` 和 `session_count`。
- `list_sessions`：返回当前活跃会话列表。
- `connect_session`：返回指定会话元数据。
- `detach_session`：结束一次接管但不关闭会话，返回 `detached`。
- `list_windows`：macOS tracked session 可用，返回该终端程序中所有窗口及其标签页的分组列表。
- `list_window_tabs`：macOS tracked session 可用，返回指定窗口内的标签页列表。
- `shutdown`：开发和验收阶段使用，生产 Mobile UI 不应暴露为默认操作。

## Managed PTY 请求

- `spawn_pty`：创建服务托管的 PTY，会话 `kind` 为 `managed_pty`。
- `read_screen`：读取 managed PTY 当前 screen buffer。
- `send_input`：向 managed PTY 写入输入。
- `resize`：调整 managed PTY 的 `cols` / `rows`，并更新 session 元数据。
- `close_session`：关闭 tracked 或 managed 会话；managed PTY 会停止子进程。

## 会话字段

- `id`：会话 ID。
- `kind`：`tracked` 或 `managed_pty`。
- `terminal_key`：同一真实终端的去重键。
- `pid` / `parent_pid`：进程信息。
- `title` / `shell` / `tab_hint`：展示用元数据。
- `cols` / `rows`：已知终端尺寸，未知时为 `null`。
- `started_at_unix_ms` / `last_seen_unix_ms`：生命周期时间戳。

## 窗口与标签页

- `list_windows` 响应：`{ "type": "windows", "session_id": "...", "windows": [{ "window_id": "...", "title": "...", "tabs": [{ "terminal_id": "...", "title": "..." }] }] }`。
- `list_window_tabs` 响应：`{ "type": "window_tabs", "session_id": "...", "window_id": "...", "tabs": [{ "terminal_id": "...", "title": "..." }] }`。
- `switch_tab` 请求：`{ "type": "switch_tab", "session_id": "...", "terminal_id": "..." }`，用于把 tracked session 绑定切换到指定标签页。
- 以上能力仅在 macOS 且 `TERM_PROGRAM` 为 `Apple_Terminal` 或 `iTerm.app` 时可用；其他平台或 managed PTY session 返回 `unsupported_operation`。

## 错误码

- `unauthorized`：token 不匹配。
- `invalid_request`：请求 JSON 无法解析。
- `unknown_session`：服务端不存在该会话；daemon 可据此在服务重启后重新注册。
- `superseded_session`：同一 `terminal_key` 已有新会话，旧 daemon 应退出。
- `unsupported_operation`：目标会话存在，但该能力在当前 adapter 上不可用。
- `pty_error`：PTY 后端操作失败。

## 当前限制

- 普通 tracked OS 终端当前只支持元数据跟踪、列表、连接和生命周期管理。
- 普通 tracked OS 终端的画面读取、输入转发和真实 attach/detach 仍需后续终端绑定能力。
- Windows ConPTY managed PTY 已实现，但需要 Windows 10 1809+。
- 窗口/标签页分组查询（`list_windows`）当前仅 macOS Terminal.app / iTerm2 支持；Windows / Linux 被跟踪终端暂无窗口分组概念。
