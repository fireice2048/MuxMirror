# 功能记忆：协议 hello 与错误码

## 背景

- 需求来源：PC 服务端六大块进度中的“服务协议”。
- 使用场景：Mobile App 通过 `auth-info` 拿到 endpoint/token 后，需要先确认服务协议版本和当前能力，再决定是否继续调用会话列表或未来的终端控制 API。

## 关键功能点

- 新增 `ClientRequest::Hello` 和 `ServerResponse::Hello`。
- 新增 `attach hello` 命令，输出 `protocol_version` 和 `capabilities`。
- `ServerResponse::Error` 新增稳定 `code` 字段。
- 当前错误码包含 `unauthorized`、`unknown_session`、`invalid_request`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`。
- 核心流程：CLI 发送带 token 的 `hello` 请求 → 服务端返回协议版本和能力列表 → Mobile 可据此做基础能力发现。
- 重要约束：本次只实现能力发现和错误码，不实现 `connect session`、`read screen`、`send input`、`resize` 的真实终端能力。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `target/debug/attach hello`、`target/debug/attach shutdown`
- 结果：单元测试通过；CLI 冒烟输出包含协议版本和能力列表。

## 后续注意事项

- 新增会话控制请求时，需要同步更新 `capabilities()`。
- 错误码应保持稳定，避免 Mobile 端只能解析自然语言错误信息。
