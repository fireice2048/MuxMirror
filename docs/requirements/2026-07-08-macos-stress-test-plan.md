# macOS 终端高频压测计划

## 背景

- macOS 终端绑定已完成真实按键输入、稳定标识、关闭检测和画面缓存。
- 剩余风险集中在大高频/长时间场景：AppleScript 进程是否泄漏、adapter 绑定是否稳定、画面缓存是否持续增长、TTY 重定位是否可靠。
- 当前测试以功能验证为主，缺少对高频轮询和多次输入-读取循环的覆盖。

## 目标

在 macOS + Terminal.app / iTerm2 真实环境下，验证服务端在较高频率的 `read_screen` / `send_input` 操作下保持稳定，无 panic、无未清理的 adapter 绑定、无明显的资源泄漏。

## 方案

### 1. 压测范围

- 平台：仅 macOS（`#[cfg(target_os = "macos")]`）。
- 终端：Terminal.app 或 iTerm2（通过 `TERM_PROGRAM` 判断）。
- 操作：
  - 高频 `read_screen`：连续 50 次调用，验证缓存命中路径稳定。
  - 输入-读取循环：连续 10 次 `send_input` + `read_screen`，验证缓存失效和画面更新稳定。

### 2. 测试设计

- 在 `PCServer/attach/src/service.rs` 的单元测试区新增 `macos_terminal_high_frequency_operations`。
- 测试流程：
  1. 获取 `ENV_LOCK` 并设置/保留 `TERM_PROGRAM`。
  2. 调用 `macos_terminal::detect_terminal_id()` 获取当前标签页标识；若当前不在 Terminal.app / iTerm2，则跳过测试。
  3. 注册一个 `Tracked` session，将 `terminal_id` 设为当前标签页标识。
  4. 连续 50 次 `read_screen`，断言每次返回 `Screen` 响应。
  5. 连续 10 次发送 `"echo attach-stress-$i\n"` 并随后 `read_screen`，断言 `InputAccepted` 和 `Screen` 响应。
  6. 断言 session 和 adapter 绑定仍存在（标签页未关闭）。
  7. 调用 `close_session` 清理，断言 session 和 adapter 绑定已被移除。

### 3. 风险与防护

- AppleScript 调用可能偶发失败，测试仅断言响应类型，不断言具体内容。
- 若当前终端不支持 AppleScript（如 CI 或 SSH session），`detect_terminal_id()` 返回 None，测试直接跳过。
- 使用 `ENV_LOCK` 避免与其他修改环境变量的测试并发。

### 4. 文档

- 更新 `docs/memory/features/2026-07-08-macos-terminal-binding.md`：记录压测已补充。
- 更新 `docs/requirements/macos-screen-cache-progress.md` 或新增压测进度文档。
- `README.md` 可简要说明已覆盖高频场景。

## 验收标准

- `cargo test -p attach` 在 macOS Terminal.app / iTerm2 环境下压测通过。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
- 压测后 session 和 adapter 绑定被正确清理。

## 限制

- 该测试依赖真实 Terminal.app / iTerm2，无法在 Linux CI 上运行，会被 `#[cfg(target_os = "macos")]` 跳过。
- 压测强度为“开发级冒烟”，非生产级压力测试；后续如需更高强度，可提取为独立 bench 或脚本。
