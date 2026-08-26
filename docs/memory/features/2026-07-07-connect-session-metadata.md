# 功能记忆：connect session 元数据连接

## 背景

- 需求来源：PC 服务端六大块进度中的“服务协议”。
- 使用场景：Mobile App 选择某个已跟踪终端后，需要先确认 session 存在并拿到元数据，再进入后续画面读取和输入控制流程。

## 关键功能点

- `connect_session` 对存在的 session 返回 `Connected { session }`。
- 新增 `attach connect <session-id>`，输出指定会话 JSON 元数据。
- 不存在的 session 继续返回 `unknown_session`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`。
- 核心流程：客户端发送带 token 的 `connect_session` 请求 → 服务端从当前 session map 查找 → 找到则返回 session 元数据。
- 重要约束：本阶段只建立“进入会话”的元数据连接，不实现 PTY 绑定、画面读取或输入转发。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `target/debug/attach register`、`target/debug/attach list`、`target/debug/attach connect <session-id>`、`target/debug/attach shutdown`
- 结果：单元测试通过；CLI 冒烟中 connect 输出指定会话元数据。

## 后续注意事项

- 实现真实终端接管后，`Connected` 可继续作为进入会话的第一步响应。
- 连接成功不代表会话画面可读；`read_screen` 仍需真实 PTY / 终端绑定能力。
