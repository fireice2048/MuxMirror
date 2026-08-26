# 功能记忆：managed PTY 画面读取

## 背景

- 需求来源：PC 服务端六大块进度中的“核心终端能力”和“服务协议”。
- 使用场景：在普通终端接管完成前，先提供服务端可管理的 Unix PTY 短命令会话，并验证 `read_screen` 能返回真实 PTY 输出。

## 关键功能点

- 新增 `spawn_pty` 请求和 `Spawned` 响应。
- `read_screen` 可读取 managed PTY session 的输出快照。
- 新增 `attach spawn-pty "<command>"` 和 `attach read-screen <session-id>`。
- 普通 tracked session 的 `read_screen` 仍返回 `unsupported_operation`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/src/pty.rs`。
- 核心流程：服务端执行短命令 PTY → 保存输出到 screen map → `read_screen` 按 PTY session id 返回输出。
- 重要约束：当前 managed PTY 是短生命周期命令输出，不是长期交互式 shell。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `target/debug/attach spawn-pty "printf attach-screen-ok"`、`target/debug/attach read-screen <session-id>`、`target/debug/attach shutdown`
- 结果：单元测试通过；CLI 冒烟中 `read-screen` 输出包含 `attach-screen-ok`。

## 后续注意事项

- 下一步需要持有长生命周期 PTY master，支持持续读取、输入写入和 resize。
- 普通终端 track 与 managed PTY 仍是两条路径，后续需要统一 session 模型。
