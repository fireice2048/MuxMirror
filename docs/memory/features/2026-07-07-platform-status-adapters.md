# 功能记忆：平台状态与终端 adapter 能力输出

## 背景

- 需求来源：PC 服务端六大块进度中的“跨平台适配”。
- 使用场景：Mobile 端和调试人员需要知道当前服务端平台、可用终端 adapter、已支持能力和明确限制，避免把未实现的普通终端 I/O 当成可用能力。

## 关键功能点

- 新增 `platform` 模块，输出 `PlatformInfo` 和 `TerminalAdapter`。
- 新增协议请求 `status` 和响应 `Status`。
- `attach status` 输出协议版本、平台信息、adapter 列表和活跃 session 数。
- macOS Terminal/iTerm2、Linux PTY、Windows ConPTY 均有服务端 adapter 描述。
- Windows ConPTY managed PTY 已实现，`windows-conpty` adapter 标记为 `available: true`，capabilities 包含 `managed_pty`；限制改为 `requires_windows_10_1809_or_later`。
- 普通 tracked terminal 画面读取/输入转发仍以 `limitations` 明确声明。

## 设计与实现

- 涉及模块：`PCServer/attach/src/platform.rs`、`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/tests/managed_pty_cli.rs`。
- 核心流程：CLI 发送 `Status` → 服务清理活跃会话 → 返回平台能力和 session count → CLI 格式化 JSON。
- 重要约束：本功能是服务端能力探测与适配边界；Windows ConPTY 已实现 managed PTY，但普通 OS 终端 I/O 仍未完成。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：38 个单元测试和 3 个集成测试通过。

## 后续注意事项

- Mobile 正式 API 可直接消费 `attach status` 判断是否展示 managed PTY、普通 tracked terminal 或平台限制提示。
- 后续实现 ConPTY 或真实终端绑定时，应更新 adapter `available`、`capabilities` 和 `limitations`。
