# macOS 终端画面轮询优化进度

本文跟踪 [2026-07-08-macos-screen-cache-plan.md](2026-07-08-macos-screen-cache-plan.md) 的执行进度。

## 任务清单

- [x] 新增 `ScreenCache` 结构与缓存读取/失效辅助函数
- [x] 为 `TerminalAppAdapter` 增加 `screen_cache` 并在 `read_screen` 中使用
- [x] 为 `Iterm2Adapter` 增加 `screen_cache` 并在 `read_screen` 中使用
- [x] `send_input` / `resize` 成功后失效缓存
- [x] 补充单元测试
- [x] 更新 README / memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy -p attach --all-targets --all-features` 无新增 warning

## 当前状态

- 全部任务已完成，代码已验证。

## 变更记录

- 2026-07-08：创建本进度文档。
