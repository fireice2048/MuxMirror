# Windows ConPTY managed PTY 实现进度

本文跟踪 [2026-07-08-windows-conpty-plan.md](2026-07-08-windows-conpty-plan.md) 的执行进度。

## 任务清单

- [x] 添加 `portable-pty` Windows 依赖
- [x] 重构 `pty.rs`：Unix 保留，`Windows` 新增 ConPTY 实现
- [x] 统一 `ManagedPty` 公共 API
- [x] 移除 `service.rs` 中 pty 相关 `cfg(unix)` 限制
- [x] 更新 `platform.rs` Windows adapter 能力/限制
- [x] Windows 单元测试条件编译并通过 `cargo check --target x86_64-pc-windows-gnu`
- [x] 更新 README / 验收文档 / memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy -p attach --all-targets --all-features` 无新增 warning

## 当前状态

- 全部任务已完成，代码已验证。

## 变更记录

- 2026-07-08：创建本进度文档。
