# Terminal.app 稳定标签页标识与关闭检测计划

## 背景

- macOS Terminal.app 当前使用 `window-id:tab-index` 作为标签页标识（`terminal_id`）。
- 当用户在 Terminal.app 内拖动标签页、关闭其他标签页或合并/拆分窗口时，`tab-index` 会变化，导致服务端仍指向错误的标签页。
- 当前没有主动检测被跟踪标签页是否已关闭的机制，关闭后 session 仍保留到 TTL 过期。

## 目标

1. 为 Terminal.app 引入更稳定的标签页标识，降低索引漂移导致的读写错误。
2. 在操作失败或被跟踪标签页消失时，能够检测到标签页关闭并清理对应 session。

## 方案

### 1. 标识扩展：加入 TTY

- Terminal.app 每个标签页都有 `tty` 属性（如 `/dev/ttys006`），在标签页存活期间相对稳定，且不会与其他存活标签页重复。
- 新的 `terminal_id` 格式：`window-id:tab-index:tty`。
- 向后兼容：解析函数允许旧格式 `window-id:tab-index` 存在，但新创建的 session 使用新格式。

### 2. 按 TTY 查找标签页

- 新增 `find_terminal_app_tab_by_tty(tty: &str) -> Option<(u32, u32)>`：遍历所有 Terminal.app 窗口和标签页，返回匹配 TTY 的 `(window_id, tab_index)`。
- 使用数字索引循环（`repeat with i from 1 to count of tabs of w`）访问 `tty` 属性，避免 AppleScript 迭代引用失效的问题。

### 3. 标签页关闭检测

- 在 `read_screen` / `send_input` / `resize` 前，先检查当前 `terminal_id` 指向的标签页 TTY 是否仍与标识一致。
- 如果索引指向的标签页 TTY 与标识中的 TTY 不一致，尝试用 `find_terminal_app_tab_by_tty` 重新定位。
- 如果按 TTY 也找不到对应标签页，判定标签页已关闭，返回 `tab_closed` 错误码。

### 4. 服务端自动重绑定或清理

- `service.rs` 收到 `tab_closed` 错误码后，移除该 session 的 `macos_adapters` 绑定，并将 session 标记为待清理。
- 在下次 `active_sessions` 扫描时，删除已关闭标签页对应的 session，避免列表中出现僵尸会话。
- 清理前记录 `info!` 日志，说明因标签页关闭而移除 session。

### 5. 测试

- 单元测试：
  - 新格式 `parse_terminal_app_id` 解析正确。
  - 旧格式解析仍兼容。
  - `find_terminal_app_tab_by_tty` 脚本生成正确。
- 集成测试：
  - 由于需要真实 Terminal.app 窗口，集成测试保持现有 `tracked_terminal_input_is_forwarded` 覆盖基础路径；关闭检测依赖人工验收。

### 6. 文档

- 更新 `docs/memory/features/2026-07-08-macos-terminal-binding.md`：记录标识方案和关闭检测逻辑。
- 更新 `docs/acceptance/pc-server-manual-acceptance.md`：补充标签页拖动/关闭后的行为验收步骤。
- 更新 `README.md`：说明 Terminal.app 标识基于 `window-id:tab-index:tty`。

## 验收标准

- `cargo test -p attach` 全部通过。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
- `attach list-tabs` 输出包含 TTY 信息。
- 在 Terminal.app 中拖动标签页改变顺序后，对应 session 的 `send-input` / `read-screen` 仍能命中原标签页。
- 关闭被跟踪标签页后，下一次 `attach list` 中该 session 消失（或短时间内被清理）。

## 风险

- `tty` 在标签页关闭后可能被系统回收并分配给新标签页，因此不能作为持久 ID；仅用于存活期内的重定位和关闭检测。
- AppleScript 访问 `tty` 属性在某些 Terminal.app 版本或沙盒环境下可能失败，需要优雅降级到原有索引方案。
