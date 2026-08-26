# Terminal.app 稳定标签页标识与关闭检测进度

本文跟踪 [2026-07-08-terminal-app-stable-id-plan.md](2026-07-08-terminal-app-stable-id-plan.md) 的执行进度。

## 任务清单

- [x] 扩展 `terminal_id` 格式为 `window-id:tab-index:tty`
- [x] 更新 `detect_current_id` 和 `list_tabs` 输出新格式
- [x] 新增按 TTY 查找标签页函数
- [x] 新增标签页关闭检测逻辑
- [x] `service.rs` 收到 `tab_closed` 后清理 session
- [x] 补充单元测试
- [x] 更新 README / 验收文档 / memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy -p attach --all-targets --all-features` 无新增 warning

## 当前状态

- 全部任务已完成，代码已验证。

## 变更记录

- 2026-07-08：创建本进度文档。
