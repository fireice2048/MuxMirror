# 功能记忆：PCServer 终端窗口与标签页查询接口

## 背景

- 需求来源：`docs/requirements/2026-07-09-terminal-window-list.md`。
- 目标：移动端进入服务器后，先展示电脑端终端的窗口列表，再展示窗口内的标签页，形成两级导航；同时支持只查询某个窗口的标签页列表。

## 关键功能点

- PCServer 协议层：
  - `WindowInfo { window_id, title, tabs: Vec<TabInfo> }`
  - `ListWindows { session_id }` → `Windows { session_id, windows }`
  - `ListWindowTabs { session_id, window_id }` → `WindowTabs { session_id, window_id, tabs }`
  - 移除旧的扁平 `ListTabs` / `Tabs`
- `MacosTerminalAdapter` trait 仅保留窗口相关能力：
  - `list_windows()`：Terminal.app 基于标签页 terminal_id 前缀分组；iTerm2 通过 AppleScript 直接按 `unique id of window` 分组。
  - `list_window_tabs(window_id)`：Terminal.app 过滤属于该 window_id 的标签页；iTerm2 从 `list_windows()` 结果中查找对应窗口。
- `service.rs` 分发 `ListWindows` / `ListWindowTabs`，仅 macOS tracked session 可用；managed PTY / 无 terminal_id / 非 macOS 返回 `unsupported_operation`。
- CLI 子命令：
  - `attach list-windows <session-id>`
  - `attach list-window-tabs <session-id> <window-id>`
  - 移除 `attach list-tabs`
- 测试覆盖：协议 round-trip、service 错误路径、CLI 集成测试对 managed PTY 返回 unsupported。

## 涉及模块

- `PCServer/attach/src/protocol.rs`
- `PCServer/attach/src/macos_terminal.rs`
- `PCServer/attach/src/service.rs`
- `PCServer/attach/src/main.rs`
- `PCServer/attach/tests/managed_pty_cli.rs`
- `docs/requirements/2026-07-09-terminal-window-list.md`
- `docs/superpowers/plans/2026-07-09-terminal-window-list.md`
- `docs/requirements/pc-mobile-api.md`
- `README.md`

## 设计与实现

- 方案选择：新增 `list_windows` 分组接口与 `list_window_tabs` 单窗口接口，移除 `list_tabs` 扁平接口。原因：用户明确要求不要扁平接口、需要两层结构、且可只查某个窗口标签页。
- iTerm2 的 `window_id` 使用 AppleScript `unique id of window`；Terminal.app 使用 `id of window`。
- 窗口标题目前为占位格式 `Window {window_id}`，后续可从 AppleScript 获取真实窗口标题再优化。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：全部测试通过，包含新增 `list_windows` / `list_window_tabs` 相关单元测试与 CLI 集成测试。
- 额外检查：`cargo fmt --all`、`cargo clippy --all-targets --all-features` 无新增警告。
- 手动验证：在 macOS Terminal.app / iTerm2 环境下启动 tracked session 后执行 `attach list-windows <session-id>` 与 `attach list-window-tabs <session-id> <window-id>` 应输出正确 JSON。

## 后续注意事项

- Mobile 端需要新增网络 client 后才能真正调用 `list_windows` / `list_window_tabs`。
- `remote-control-shared` 已定义 `TerminalTab` / `TerminalWindow` / `TerminalWindowList`，下一阶段 App 导航改造时可直接对接。
- Windows / Linux 被跟踪终端暂无窗口分组概念，后续若需支持需单独设计。
- iTerm2 / Terminal.app 窗口真实标题可后续增强，当前占位不影响 Mobile 导航逻辑。
