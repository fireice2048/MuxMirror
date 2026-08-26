# 功能记忆：显式 session kind

## 背景

- 需求来源：managed PTY 和普通 `attach track` 会话已经共用 `list/connect`，但此前只能通过 `tab_hint` 猜测类型。
- 使用场景：Mobile App 渲染会话列表和决定可用操作时，需要稳定字段区分会话来源。

## 关键功能点

- `TerminalSession` 新增 `kind` 字段。
- 普通 track/register 会话为 `tracked`。
- managed PTY 会话为 `managed_pty`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/session.rs`、`PCServer/attach/src/service.rs`。
- 核心流程：会话创建时写入 kind → `list` 和 `connect` 原样返回。
- 重要约束：`kind` 只表达会话来源，不代表所有操作均可用；普通 tracked session 仍不支持 read/input/resize。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试通过，覆盖 tracked 和 managed PTY kind。

## 后续注意事项

- Mobile 正式 API 文档应把 `kind` 作为必读字段。
