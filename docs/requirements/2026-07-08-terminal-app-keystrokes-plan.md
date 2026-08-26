# Terminal.app 真实按键输入与权限引导实现计划

## 背景

- macOS 终端绑定已完成，但 Terminal.app 的 `send_input` 当前使用 `do script "printf '%s' \"...\""` 降级方案。
- 该方案会污染 shell 历史，且不是真实按键输入，无法触发 readline 补全、快捷键等交互行为。
- 通过 `System Events` 的 `keystroke` 可以发送真实按键，但需要 Accessibility 权限。
- Accessibility 权限是本地用户授权机制，个人开发者无门槛，只需引导用户在系统设置中开启。

## 目标

1. 在 Terminal.app 上优先通过 `System Events` 发送真实按键。
2. 未获得 Accessibility 权限时自动降级到 `do script`，同时提示用户如何授权。
3. 提供权限检测和引导，让用户知道如何开启以获得更好体验。

## 技术方案

1. **权限检测**
   - 新增 `has_accessibility_permission()`：执行一个轻量的 `System Events` AppleScript 探针（如获取第一个应用进程名）。
   - 如果返回 `-1743` 权限错误，认为未授权；其他错误按失败处理。

2. **真实按键输入**
   - 新增 `send_input_via_system_events(terminal_id, input)`：
     - 通过 Terminal.app AppleScript 激活目标窗口/标签页。
     - 通过 `System Events` 对 Terminal.app 进程发送 `keystroke`。
   - 输入中的特殊字符（如 `\n`）映射为 `key code 36`（Return），`\t` 映射为 `key code 48`（Tab），`\e` 映射为 `key code 53`（Escape）。

3. **降级策略**
   - `TerminalAppAdapter::send_input`：
     1. 检查是否有 Accessibility 权限。
     2. 有权限 → 走 `System Events` 真实按键。
     3. 无权限 → 走 `do script` 降级方案，并附带 warning 日志/提示。

4. **CLI 提示**
   - 当 `send-input` 因无 Accessibility 权限而降级时，服务端返回 `InputAccepted`，但在 response 中增加 `note` 字段或返回特殊 warning 码。
   - 或者：服务端不破坏协议，仅记录 warning 日志；CLI 侧检测到无权限时主动打印引导信息。
   - 本阶段选择：服务端返回 `InputAccepted` 并记录 warning；CLI 执行 `send-input` 前主动检测权限，若无权限则打印引导信息。

5. **平台能力声明**
   - Terminal.app adapter limitations 更新为：
     - `tracked_terminal_io_requires_applescript_permission`
     - `terminal_app_input_requires_accessibility_permission_for_real_keystrokes`
     - `screen_content_may_be_stale_due_to_polling`

## 任务拆分

1. `macos_terminal.rs`：新增 `has_accessibility_permission()` 和 `send_input_via_system_events()`。
2. `macos_terminal.rs`：修改 `TerminalAppAdapter::send_input`，实现权限检测 + 真实按键 + 降级。
3. `main.rs`：CLI `send-input` 执行前检测 Terminal.app 权限并打印引导（macOS only）。
4. `platform.rs`：更新 Terminal.app adapter limitations。
5. 添加单元测试：验证特殊字符映射、权限检测不 panic。
6. 更新 `README.md`、验收文档、memory。

## 风险与约束

- `System Events` 首次调用会触发系统弹窗，需要用户授权；授权后需要重新运行命令。
- 多字符输入通过 `keystroke` 发送，特殊字符需要正确映射为 key code，否则可能产生乱码或无法触发。
- 用户切换到其他应用时，`System Events` 仍会把按键发给 Terminal.app，但需要在脚本中先 activate Terminal。
- 本实现仅针对 Terminal.app；iTerm2 保持现有的 `write text` 方案。

## 验收标准

- macOS Terminal.app 中，授权 Accessibility 后，`attach send-input` 发送的文本像真实按键一样出现在终端，不污染 shell 历史。
- 未授权时，`attach send-input` 仍能工作（降级到 `do script`），CLI 会提示用户去系统设置开启权限。
- `cargo test -p attach` 全部通过。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
