# BugFix 记忆：JSON 不支持 u128 时间戳

## 现象

- 触发条件：执行 `attach register` 时，CLI 将 `TerminalSession` 序列化为 JSON 请求发送给本机服务。
- 用户影响：注册当前终端会话失败，命令输出 `Error: u128 is not supported`。

## 根因

- `TerminalSession.started_at_unix_ms` 使用 `u128` 保存 `SystemTime::as_millis()`。
- `serde_json` 不支持直接序列化/反序列化 `u128`。

## 修复方案

- 涉及模块：`PCServer/attach/src/session.rs`、`PCServer/attach/src/protocol.rs`。
- 关键改动：将 `started_at_unix_ms` 改为 `u64`，并在生成时间戳时做上限保护；新增 JSON 往返测试覆盖 `ClientRequest::Register`。

## 验证方式

- 复现步骤：新增测试 `protocol::tests::register_request_round_trips_as_json`，修复前失败。
- 验证命令：`cargo test -p attach protocol::tests::register_request_round_trips_as_json`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test -p attach`、`ATTACH_SERVICE_ADDR=127.0.0.1:48731 cargo run -p attach -- register && ATTACH_SERVICE_ADDR=127.0.0.1:48731 cargo run -p attach -- list`。
- 验证结果：回归测试、clippy、完整测试和 CLI 冒烟均通过。

## 预防措施

- 协议结构新增字段时，优先使用 JSON 兼容类型。
- 为跨进程请求补充序列化/反序列化往返测试。
