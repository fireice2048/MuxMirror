# 反馈记忆：daemon 恢复测试与 nonblocking socket

## 坑点描述

- `TcpListener` 设置为 nonblocking 后，macOS 上 accept 出来的 client stream 也可能表现为 nonblocking。
- 如果直接在线程里 `read_line`，客户端刚连上但请求体还没到时会触发 WouldBlock，服务端提前关闭连接，客户端看到 `EOF while parsing` 或 `Connection reset by peer`。

## 触发条件

- daemon 注册或服务重启恢复时，短时间内连续发送 `hello`、`register`、`list`。
- 服务端把 listener 设为 nonblocking，但未把 accepted stream 改回 blocking。

## 正确做法

- accepted stream 进入 client handler 后先调用 `set_nonblocking(false)`，再设置 read timeout。
- 服务重启后 daemon 重注册必须复用带重试的注册函数，并更新本地 `session_id`。
- CLI 集成测试使用全局锁串行运行，避免多个本地服务和 PTY 压测互相影响。
- 测试结束时显式 `kill` 并 `wait` daemon，避免残留后台进程。

## 验证方式

- 命令：`cargo test -p attach tracking_daemon_recovers_after_service_restart -- --nocapture`
- 结果：测试通过。
