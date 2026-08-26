# 功能记忆：已退出 managed PTY 自动清理

## 背景

- 需求来源：稳定性与性能中的资源占用优化。
- 使用场景：短命令 managed PTY 结束后，不应长期留在服务内存和会话列表中。

## 关键功能点

- `ManagedPty` 支持检测 child 是否退出。
- `list_sessions` 前清理已退出的 managed PTY。
- 清理 PTY map 后同步移除对应 `managed_pty` session。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`、`PCServer/attach/src/service.rs`。
- 核心流程：list → retain active sessions → remove exited ptys → remove orphan managed PTY sessions。
- 重要约束：普通 tracked session 仍按 heartbeat TTL 清理，不受 child 检测影响。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试通过，覆盖已退出 managed PTY list 前清理。

## 后续注意事项

- 如果后续需要保留已退出会话的最后屏幕，应改为 exited 状态而不是直接移除。
