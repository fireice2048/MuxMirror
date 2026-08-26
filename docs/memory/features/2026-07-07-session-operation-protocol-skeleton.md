# 功能记忆：会话操作协议骨架

## 背景

- 需求来源：PC 服务端六大块进度中的“服务协议”。
- 使用场景：Mobile App 需要稳定的请求/响应类型来接入终端会话控制；真实 PTY 绑定尚未完成前，先固定协议名称和错误语义。

## 关键功能点

- 新增 `connect_session`、`read_screen`、`send_input`、`resize` 请求类型。
- `hello` 能力列表同步包含上述会话操作能力名。
- 服务端会先校验 `session_id` 是否存在。
- 已知会话在真实能力未实现时返回 `unsupported_operation`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`。
- 核心流程：Mobile 发送带 token 的会话操作请求 → 服务端检查 session 是否存在 → 真实 PTY 能力完成前返回稳定错误码。
- 重要约束：本阶段不实现终端画面同步、输入转发或 resize 的实际效果。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `target/debug/attach hello`、`target/debug/attach shutdown`
- 结果：单元测试通过；`hello` 输出包含会话操作能力名。

## 后续注意事项

- 实现真实 PTY 后，应将 `unsupported_operation` 替换为实际 `connected`、`screen`、`input_accepted`、`resized` 响应。
- 不存在的 session 继续返回 `unknown_session`，避免 Mobile 混淆“会话不存在”和“能力未实现”。
