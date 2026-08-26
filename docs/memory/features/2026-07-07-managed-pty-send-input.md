# 功能记忆：managed PTY 输入写入

## 背景

- 需求来源：PC 服务端六大块进度中的“核心终端能力”和“服务协议”。
- 使用场景：Mobile App 需要向 managed PTY 会话发送输入，并读取终端输出变化。

## 关键功能点

- `ManagedPty` 持有 PTY master 和 child，支持长期命令。
- `send_input` 将输入写入 PTY master。
- `read_screen` 返回累计 PTY 输出。
- 新增 `attach send-input <session-id> <input>`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`。
- 核心流程：`spawn_pty` 创建 managed PTY → `send_input` 写入 master → `read_screen` drain 输出并返回 screen。
- 重要约束：当前 screen 是累计字符串快照；还没有终端缓冲区模型、ANSI 解析或 resize。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `spawn-pty "cat"`、`send-input <id> $'attach-input-ok\n'`、`read-screen <id>`、`shutdown`
- 结果：单元测试通过；CLI 冒烟中 `read-screen` 输出包含 `attach-input-ok`。

## 后续注意事项

- 下一步实现 `resize`，并考虑 screen buffer 上限，避免长期会话无限增长。
- 普通 tracked session 仍未接入 managed PTY 能力。
