# BugFix 记忆：服务端空闲连接阻塞

## 现象

- 触发条件：TCP 客户端连接 Attach service 后不发送 JSON line 请求。
- 用户影响：服务端原先在单连接 `read_line` 上阻塞，后续 Mobile 或 CLI 请求无法及时处理。

## 根因

- `service::run` 在主 accept 循环内同步执行 `handle_client`。
- 单个慢客户端会占住服务主循环，直到该连接发送换行或断开。
- service 原先先 bind 端口、后加载 token；CLI 看到端口可连接后可能与 service 并发初始化 token，导致服务启动失败并 reset 首个真实请求。
- client 原先先 connect、后加载 token；服务端读超时较短时，慢 token I/O 会让正常请求被误判为空闲连接。
- token 文件使用 `create_new` 后写入，另一个进程可能在写入完成前读到空文件。

## 修复方案

- 涉及模块：`PCServer/attach/src/service.rs`、`PCServer/attach/tests/managed_pty_cli.rs`。
- 关键改动：service 先加载 token 再 bind 端口；client 先加载 token 再 connect；读到空 token 时短暂重试；CLI 等待真实 `hello` 成功后才认为服务可用；Unix service 和 tracking daemon 单独 process group 启动；`track` 尊重已有 `ATTACH_PARENT_PID` 覆盖值；tracking daemon 首次注册短重试；listener 改为 nonblocking accept；每个客户端读取请求行时设置短 read timeout；EOF 或空行请求直接忽略，不回写错误响应。

## 验证方式

- 复现步骤：启动 service，打开一个不发送数据的 TCP 连接，再执行 `attach hello`。
- 验证命令：`cargo test -p attach idle_client_does_not_block_other_requests`
- 验证结果：修复前 `hello` 超时；修复后测试通过。

## 预防措施

- 涉及服务端连接处理的改动应覆盖慢客户端或异常客户端不影响正常请求。
- EOF 或空行探测不能回写响应，避免客户端已关闭时触发连接 reset。
