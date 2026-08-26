# 功能记忆：managed PTY resize

## 背景

- 需求来源：PC 服务端六大块进度中的“核心终端能力”和“服务协议”。
- 使用场景：Mobile App 连接 managed PTY 后，需要根据手机端终端视图调整远端 PTY 窗口大小。

## 关键功能点

- `ManagedPty::resize` 在 Unix 使用 `TIOCSWINSZ`，在 Windows 使用 `portable-pty` 的 `MasterPty::resize`（ConPTY）。
- `resize` 请求对 managed PTY 返回 `Resized { session_id, cols, rows }`。
- 新增 `attach resize <session-id> <cols> <rows>`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/src/protocol.rs`。
- 核心流程：MobileClient/CLI 发送 resize 请求 → 服务端找到 managed PTY → 调用 ioctl 设置窗口大小 → 返回确认响应。
- 重要约束：普通 tracked session 尚未接入 managed PTY，因此 resize 对普通 tracked session 仍不可用。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `spawn-pty "cat"`、`resize <id> 120 32`、`shutdown`
- 结果：单元测试通过；CLI 冒烟中 resize 退出码为 0。

## 后续注意事项

- 需要将 managed PTY 与普通 `attach track` session 的模型关系梳理清楚。
- 后续如支持 Windows，应以 ConPTY 实现对应 resize（已完成：通过 `portable-pty` 实现）。
