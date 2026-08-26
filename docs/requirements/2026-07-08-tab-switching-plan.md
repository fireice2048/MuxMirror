# 标签页切换同步实现计划

## 背景

- macOS 终端绑定已实现：Terminal.app 和 iTerm2 的画面同步、输入转发、窗口大小调整和标签页标题识别。
- 当前 `attach track` 启动时绑定的是用户当前所在的标签页；用户切换标签页后，服务端仍指向原标签页，Mobile 端无法主动选择其他标签页。
- `docs/requirements/macos-terminal-binding-progress.md` 已将"标签页切换同步 / Mobile 端可选标签页"列为后续待办事项。

## 目标

让 Mobile 端能够列出被跟踪终端的可用标签页，并切换到指定标签页，切换后 `read-screen` / `send-input` / `resize` 均针对新标签页生效。

## 技术方案

1. **协议扩展**
   - 新增 `ClientRequest::ListTabs { session_id }`：返回指定 tracked session 当前终端程序的所有标签页。
   - 新增 `ClientRequest::SwitchTab { session_id, terminal_id }`：将指定 tracked session 的绑定切换到给定标签页标识。
   - 新增 `ServerResponse::Tabs { session_id, tabs }`：标签页列表。
   - 新增 `ServerResponse::SwitchedTab { session_id, terminal_id }`：切换成功响应。
   - `TabInfo` 序列化字段：`terminal_id`、`title`。

2. **CLI 命令**
   - `attach list-tabs <session-id>`：输出 JSON 数组。
   - `attach switch-tab <session-id> <terminal-id>`：切换绑定。

3. **服务端实现**
   - `service.rs` 新增 `list_tabs(session_id)`：校验 session 存在且为 tracked session，调用 macOS adapter 的 `list_tabs()`。
   - `service.rs` 新增 `switch_tab(session_id, terminal_id)`：更新 `session.terminal_id`，清理旧的 `macos_adapters` 绑定，返回 `SwitchedTab`。
   - 清理旧的 adapter 绑定确保下次 `read/send/resize` 使用新的 `terminal_id` 重新绑定。

4. **macOS adapter 调整**
   - `macos_terminal::TabInfo` 增加 `Serialize` / `Deserialize` 派生。
   - `list_tabs()` 已存在，无需重写。

5. **能力声明**
   - protocol capabilities 增加 `list_tabs`、`switch_tab`。
   - macOS adapter capabilities 增加 `tab_switching`。

## 任务拆分

1. `protocol.rs`：新增 `ListTabs`、`SwitchTab` 请求和 `Tabs`、`SwitchedTab` 响应。
2. `macos_terminal.rs`：`TabInfo` 增加 serde 支持。
3. `service.rs`：新增 `list_tabs` / `switch_tab` 处理，更新 `handle_request` match。
4. `main.rs`：新增 `list-tabs` / `switch-tab` 子命令和对应函数。
5. `platform.rs`：更新 macOS adapter capabilities 和 limitations。
6. 添加单元测试：验证 `switch_tab` 更新 terminal_id 并清理 adapter 绑定。
7. 添加集成测试：手动构造带 terminal_id 的 tracked session，验证 `list-tabs` / `switch-tab` CLI 流程。
8. 更新 `README.md`、验收文档、memory。

## 风险与约束

- `list_tabs()` 依赖 `osascript`，枚举所有窗口/标签页可能有性能开销；当前原型阶段可接受。
- Terminal.app 的 `terminal_id` 使用 `window-id:tab-index`，切换后若窗口/标签页顺序变化，索引可能失效。iTerm2 的 session unique id 更稳定。
- `switch-tab` 只更新服务端绑定，不会主动在终端模拟器中切换视觉焦点。
- 非 macOS 平台或没有 `terminal_id` 的 tracked session 返回 `unsupported_operation`。

## 验收标准

- macOS Terminal.app 或 iTerm2 中启动 `attach track` 后，`attach list-tabs <session-id>` 能输出可用标签页 JSON 数组。
- `attach switch-tab <session-id> <terminal-id>` 后，再次 `read-screen` / `send-input` 针对新标签页生效。
- `cargo test -p attach` 全部通过。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
