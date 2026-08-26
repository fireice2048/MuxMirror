# Terminal.app 真实按键输入与权限引导实现进度

本文跟踪 [2026-07-08-terminal-app-keystrokes-plan.md](2026-07-08-terminal-app-keystrokes-plan.md) 的执行进度。

## 任务清单

- [x] `macos_terminal.rs` 新增 Accessibility 权限检测
- [x] `macos_terminal.rs` 实现 System Events 真实按键输入
- [x] `TerminalAppAdapter::send_input` 优先真实按键并降级到 `do script`
- [x] CLI `send-input` 打印权限引导提示
- [x] `platform.rs` 更新 Terminal.app adapter limitations
- [x] 补充单元测试与集成测试
- [x] 更新 `README.md`、验收文档、memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy --all-targets --all-features` 无新增 warning

## 当前状态

- 全部任务已完成，代码已验证。

## 变更记录

- 2026-07-08：创建本进度文档。
