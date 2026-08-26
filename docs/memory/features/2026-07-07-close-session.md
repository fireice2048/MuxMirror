# 功能记忆：会话主动关闭

## 背景

- 需求来源：稳定性与性能中的资源清理。
- 使用场景：managed PTY 是长期子进程，用户或 Mobile 需要主动关闭，避免进程残留。

## 关键功能点

- 新增 `close_session` 请求和 `Closed` 响应。
- 新增 `attach close <session-id>`。
- 关闭 managed PTY 时移除 session 记录并 drop PTY，触发子进程 kill/wait。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`。
- 核心流程：close 请求 → 从 sessions 移除 → 从 managed PTY map 移除 → 后续 read/connect 返回 `unknown_session`。
- 重要约束：本阶段不是旧 daemon 自动清理；普通 `attach track` daemon 生命周期仍需单独处理。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `spawn-pty "cat"`、`close <id>`、`read-screen <id>`、`shutdown`
- 结果：单元测试通过；CLI 冒烟中 close 后 read-screen 失败为 unknown session。

## 后续注意事项

- 后续需要给普通 tracked daemon 增加真实生命周期退出或替换机制。
