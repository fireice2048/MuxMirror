# 功能记忆：Mobile API 草案与终端尺寸元数据

## 背景

- 需求来源：PC 服务端六大块进度中的“服务协议”和“核心终端能力”。
- 使用场景：Mobile 端需要稳定协议文档接入服务端，并需要知道 managed PTY 当前终端尺寸。

## 关键功能点

- 新增 `docs/requirements/pc-mobile-api.md`，记录 JSON line 传输、鉴权、请求、响应、错误码和当前限制。
- `TerminalSession` 新增 `cols` / `rows` 元数据。
- managed PTY 创建时记录初始尺寸。
- managed PTY resize 成功后更新 session 尺寸元数据。

## 设计与实现

- 涉及模块：`PCServer/attach/src/session.rs`、`PCServer/attach/src/service.rs`、`docs/requirements/pc-mobile-api.md`、`README.md`。
- 核心流程：`spawn_pty` 写入初始尺寸 → `resize` 调整 PTY 并更新 session → `connect` / `list` 暴露最新尺寸。
- 重要约束：尺寸元数据适用于已知尺寸；普通 tracked terminal 尺寸来自环境变量，未知时为 `null`。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试和集成测试通过，覆盖 resize 后 connect 可看到新尺寸。

## 后续注意事项

- Mobile 端联调时应以 `status` 和 `hello` 做能力发现，再调用 managed PTY API。
- 普通 tracked terminal 的真实 I/O 和 attach/detach 仍需后续能力，不在本次协议完成范围内。
