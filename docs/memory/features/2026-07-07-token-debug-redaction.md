# 功能记忆：token 调试脱敏

## 背景

- 需求来源：安全与连接中的敏感信息保护。
- 使用场景：服务端处理授权请求时，调试输出不应泄露 token。

## 关键功能点

- `AuthenticatedRequest` 自定义 `Debug`。
- Debug 输出中的 `token` 固定显示为 `<redacted>`。
- 序列化协议不变，客户端请求仍携带真实 token。

## 设计与实现

- 涉及模块：`PCServer/attach/src/protocol.rs`。
- 核心流程：serde 继续正常编解码；仅 `format!("{request:?}")` 等调试输出脱敏。
- 重要约束：不要在日志中手动打印 token；如新增 auth 相关结构，也应实现脱敏 Debug。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试通过，覆盖 Debug 输出不包含真实 token。

## 后续注意事项

- 后续引入请求日志时，应记录 request type，不记录完整 auth envelope。
