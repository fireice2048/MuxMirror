# 功能记忆：Attach 会话心跳与后台跟踪

## 背景

- 需求来源：继续开发 PC 端 Attach 原型。
- 使用场景：用户将 `attach` 放入 `~/.zshrc` 后不能阻塞 shell，同时服务列表不能长期保留已退出终端。

## 关键功能点

- 默认 `attach` 等价于 `attach track`，会启动后台跟踪进程并立即返回。
- `attach daemon` 为内部命令，负责注册当前终端并周期发送心跳。
- 服务新增 `Heartbeat` 协议，收到心跳后刷新 `last_seen_unix_ms`。
- `attach list` 查询时按 TTL 清理过期会话，避免僵尸终端长期展示。

## 设计与实现

- 涉及模块：`PCServer/attach/src/main.rs`、`protocol.rs`、`service.rs`、`session.rs`。
- 核心流程：`track` 拉起 `daemon` → `daemon` 注册会话 → 每 5 秒发送心跳 → 服务按 15 秒 TTL 保留活跃会话。
- 重要约束：当前心跳进程会随终端环境独立运行；后续需要与真实 PTY/终端生命周期绑定，避免父终端退出后仍继续心跳。

## 验证方式

- 命令：`cargo test -p attach service::tests`
- 命令：`cargo clippy --all-targets --all-features -- -D warnings`
- 命令：`cargo test -p attach`
- 命令：`ATTACH_SERVICE_ADDR=127.0.0.1:48734 target/debug/attach track && ATTACH_SERVICE_ADDR=127.0.0.1:48734 target/debug/attach list`
- 结果：单元测试、clippy 和 CLI 冒烟通过，`track` 后列表能展示后台跟踪会话。

## 后续注意事项

- 需要实现终端生命周期检测，父终端退出后应停止心跳。
- 需要设计更安全的本机服务访问控制和 SSH 后服务发现。
