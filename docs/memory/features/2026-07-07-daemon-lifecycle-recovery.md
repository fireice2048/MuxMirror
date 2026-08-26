# 功能记忆：daemon 生命周期与服务恢复

## 背景

- 需求来源：PC 服务端六大块进度中的“稳定性与性能”。
- 使用场景：服务崩溃或被重启后，已存在的后台跟踪 daemon 应继续恢复会话；同一终端重复执行 `track` 后，旧 daemon 不应长期残留；真实终端退出后 daemon 应停止。

## 关键功能点

- `Heartbeat` 请求可携带 `terminal_key`，服务端可区分服务重启后的未知会话和已被替代的旧会话。
- daemon 收到 `unknown_session` 时会重新注册，覆盖服务重启后的空状态。
- daemon 收到 `superseded_session` 时会退出，避免同一终端重复 `track` 后旧 daemon 残留。
- `track` 启动 daemon 时传入被跟踪父终端 PID；daemon 检测父进程不存在后关闭会话并退出。
- 服务端清理 stale session 和 exited managed PTY 时统一走 `close_session`，确保资源释放路径一致。

## 设计与实现

- 涉及模块：`PCServer/attach/src/main.rs`、`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/session.rs`、`PCServer/attach/tests/managed_pty_cli.rs`。
- 核心流程：daemon 心跳 → 服务返回 accepted / unknown / superseded → daemon 继续、重注册或退出。
- 重要约束：当前普通 tracked session 仍是元数据跟踪，不等于已支持普通 OS 终端画面同步或输入转发。

## 验证方式

- 命令：`cargo test -p attach service::tests:: -- --nocapture`
- 命令：`cargo test -p attach tracking_daemon_recovers_after_service_restart -- --nocapture`
- 结果：服务端单元测试和服务重启恢复集成测试通过。

## 后续注意事项

- 后续实现真实普通终端 attach/detach 时，需要用更可靠的终端/PTY 标识替代当前基于父进程 PID 的 `terminal_key`。
- Windows 端需要补充基于平台 API 的进程存活检测，目前非 Unix 平台保守返回存活。
