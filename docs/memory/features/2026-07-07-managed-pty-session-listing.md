# 功能记忆：managed PTY 列表与连接接入

## 背景

- 需求来源：managed PTY 已支持读屏、输入和 resize，但此前没有进入 `list/connect` 会话流程。
- 使用场景：Mobile App 需要统一从会话列表进入 managed PTY，而不是维护另一套隐藏 ID。

## 关键功能点

- `spawn_pty` 同时注册一条 `TerminalSession`。
- managed PTY 出现在 `list_sessions` 输出中。
- `connect_session` 可返回 managed PTY 的元数据。
- `read_screen`、`send_input`、`resize` 会刷新 managed PTY 的 `last_seen_unix_ms`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/service.rs`、`PCServer/attach/src/pty.rs`。
- 核心流程：spawn managed PTY → 生成 `pty-*` session id → 插入 sessions 和 ptys → list/connect 复用现有会话流程。
- 重要约束：普通 `attach track` 会话与 managed PTY 会话仍是不同来源，后续需要统一模型或在协议中显式区分。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `spawn-pty "cat"`、`list`、`connect <id>`、`shutdown`
- 结果：单元测试通过；CLI 冒烟中 list/connect 均能看到 managed PTY。

## 后续注意事项

- 需要限制 managed PTY screen buffer 大小，避免长期输出无限增长。
- TTL 清理会同步移除过期 managed PTY。
