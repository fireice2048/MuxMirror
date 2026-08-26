# 功能记忆：标签页切换同步

## 背景

- macOS 终端绑定完成后，Mobile 端可以查看被跟踪终端的画面并发送输入，但 `attach track` 启动时只绑定当前标签页。
- 用户切换 Terminal.app / iTerm2 标签页后，服务端仍指向原标签页，Mobile 端无法主动选择其他标签页。

## 关键功能点

- 协议新增 `list_tabs` 和 `switch_tab` 能力。
- `ClientRequest::ListTabs { session_id }` 返回指定 tracked session 可用标签页列表。
- `ClientRequest::SwitchTab { session_id, terminal_id }` 更新 session 的 `terminal_id` 并清理旧的 macOS adapter 绑定。
- CLI 新增 `attach list-tabs <session-id>` 和 `attach switch-tab <session-id> <terminal-id>`。
- macOS adapter capabilities 增加 `tab_switching`。

## 设计与实现

- 涉及模块：`protocol.rs`、`service.rs`、`main.rs`、`platform.rs`。
- 核心流程：
  1. Mobile 端调用 `list_tabs` 获取可用标签页。
  2. 用户选择目标标签页后调用 `switch_tab`。
  3. 服务端更新 `session.terminal_id`，移除旧的 `macos_adapters` 绑定。
  4. 后续 `read_screen` / `send_input` / `resize` 使用新的 `terminal_id` 重新绑定。
- 重要约束：
  - 只对 macOS tracked session 有效；其他平台或没有 `terminal_id` 的 session 返回 `unsupported_operation`。
  - `list_tabs` 依赖 `osascript` 枚举所有窗口/标签页，有一定开销。
  - Terminal.app 使用 `window-id:tab-index` 作为标识，窗口/标签页顺序变化后索引可能失效；iTerm2 使用 session unique id 更稳定。
  - `switch-tab` 只更新服务端绑定，不会主动切换终端模拟器的视觉焦点。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：51 个单元测试 + 3 个 managed PTY 集成测试 + 1 个 tracked terminal 集成测试全部通过。
- 命令：`cargo clippy -p attach --all-targets --all-features`
- 结果：无 warning。

## 当前限制

- 尚未在 Mobile UI 中闭环；当前仅提供协议和 CLI。
- Terminal.app 标签页索引在窗口顺序变化后可能失效。
- `list_tabs` 调用 `osascript`，高频使用有性能开销。

## 后续待办

- [ ] 在 Mobile 端实现标签页列表 UI 和切换操作。
- [ ] 考虑为 Terminal.app 使用更稳定的标签页标识。
- [ ] 优化 `list_tabs` 性能或增加缓存。
