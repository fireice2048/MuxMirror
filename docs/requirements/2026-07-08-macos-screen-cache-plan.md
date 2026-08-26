# macOS 终端画面轮询优化计划

## 背景

- macOS Terminal.app / iTerm2 的画面同步依赖 `read-screen` 调用 `osascript` 读取标签页内容。
- 每次调用都启动 `osascript` 进程，在高频轮询或大量标签页场景下开销明显。
- 当前没有缓存机制，即使画面内容未变化也会重复执行 AppleScript。

## 目标

为 macOS terminal adapter 引入短期画面内容缓存，降低高频 `read-screen` 轮询对 AppleScript / `osascript` 的调用次数，同时保证输入或尺寸变化后能及时读到新内容。

## 方案

### 1. 缓存结构

- 在 `TerminalAppAdapter` 和 `Iterm2Adapter` 中增加 `screen_cache: Mutex<Option<ScreenCache>>`。
- `ScreenCache` 包含 `content: String` 和 `fetched_at: Instant`。
- 缓存 TTL：200ms（可在后续根据实际轮询频率调整）。

### 2. 缓存读取

- `read_screen` 先检查缓存：
  - 若缓存存在且在 TTL 内，直接返回缓存内容。
  - 否则执行 AppleScript 读取，写入缓存，再返回。
- 读取失败时不更新缓存，避免把错误内容缓存起来。

### 3. 缓存失效

- `send_input` 成功返回后清空缓存：输入会改变终端画面，下次 `read_screen` 应读到最新内容。
- `resize` 成功返回后清空缓存：窗口尺寸变化后内容布局会变化。
- `switch-tab` 会移除旧 adapter 绑定并创建新 adapter，新 adapter 缓存为空，无需额外处理。

### 4. 线程安全

- adapter 以 trait object 形式存储在 `service.rs` 的 `macos_adapters` 中，`read_screen` / `send_input` / `resize` 方法接收 `&self`。
- 使用 `std::sync::Mutex` 实现内部可变性。
- `service.rs` 在单线程内处理每个请求（通过 `Mutex<ServiceState>` 加锁），实际竞争极低，但仍使用 Mutex 保证 trait 接口不变。

### 5. 测试

- 单元测试：
  - 缓存命中时返回旧内容，不调用 fetch。
  - 缓存过期时调用 fetch 并更新缓存。
  - `invalidate_screen_cache` 清空缓存。
- 集成测试：
  - 现有 `tracked_terminal_input_is_forwarded` 继续覆盖基础路径。

### 6. 文档

- 更新 `docs/memory/features/2026-07-08-macos-terminal-binding.md`：记录缓存策略和失效条件。
- 更新 `docs/requirements/terminal-app-stable-id-progress.md` 旁的 memory，或新增优化进度文档。
- `README.md` 可简要说明画面同步带缓存。

## 验收标准

- `cargo test -p attach` 全部通过。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
- 高频 `attach read-screen` 在 TTL 内不会每次都启动 `osascript`（可通过日志或耗时观察）。
- `send-input` / `resize` 后下一次 `read-screen` 能读到更新后的内容。

## 风险

- TTL 过长会导致画面更新延迟；TTL 过短则优化效果有限。200ms 是一个折中起点。
- 缓存仅对同一 adapter 实例有效；`switch-tab` 后新 adapter 缓存为空，首次 `read-screen` 仍会调用 AppleScript。
- 如果外部应用修改了终端画面而 Attach 未感知（未调用 send_input/resize），缓存会在 TTL 后自动过期，不会长期不一致。
