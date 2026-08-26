# 功能记忆：显式 detach 会话协议

## 背景

- 需求来源：核心终端能力中的会话接管 / attach / detach。
- 使用场景：Mobile 端进入会话后需要能显式退出接管，但不关闭服务端会话或 managed PTY 子进程。

## 关键功能点

- 新增协议请求 `detach_session`。
- 新增响应 `detached`。
- 新增 CLI 命令 `attach detach <session-id>`。
- detach 刷新会话 `last_seen_unix_ms`，但不移除 session，也不关闭 managed PTY。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/tests/managed_pty_cli.rs`。
- 核心流程：MobileClient/CLI 调用 detach → 服务确认 session 存在 → 刷新 last_seen → 返回 detached。
- 重要约束：关闭会话仍使用 `close_session`；detach 不能释放 PTY 资源。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试覆盖 detach 不关闭会话；集成测试覆盖 CLI detach 后 list 仍包含 session。

## 后续注意事项

- Mobile UI 中返回会话列表/退出终端视图应调用 detach，销毁会话才调用 close。
