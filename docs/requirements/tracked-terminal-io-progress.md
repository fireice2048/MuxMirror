# 普通被跟踪终端 I/O 实现进度

本文跟踪 [2026-07-08-tracked-terminal-io-plan.md](2026-07-08-tracked-terminal-io-plan.md) 的执行进度。

## 任务清单

- [x] 新增 `PCServer/attach/src/tracked_tty.rs` 模块，封装 TTY 检测、打开、读写、resize 和 screen buffer
- [x] `PCServer/attach/src/session.rs` 增加 `tty_path: Option<String>` 字段
- [x] `PCServer/attach/src/main.rs` 的 `track_current_terminal` 在注册前检测并设置 `tty_path`
- [x] `PCServer/attach/src/service.rs` 为 tracked session 维护 `tracked_ttys`，处理 read/send/resize
- [x] `PCServer/attach/src/platform.rs` 更新能力声明
- [x] `PCServer/attach/src/protocol.rs` 添加 `tracked_terminal_io` capability
- [x] 添加单元测试和集成测试
- [x] 更新 `README.md` 和验收文档
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy --all-targets --all-features` 无新增 warning

## 当前状态

- 2026-07-08：完成普通被跟踪终端 I/O 基础实现，输入转发可用，画面读取受终端模拟器和权限限制。
- 已补充 `docs/memory/features/2026-07-08-tracked-terminal-io.md`。

## 变更记录

- 2026-07-08：创建本进度文档。
- 2026-07-08：完成全部任务并更新本文。
