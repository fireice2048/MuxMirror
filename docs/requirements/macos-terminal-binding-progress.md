# macOS 终端绑定实现进度

本文跟踪 [2026-07-08-macos-terminal-binding-plan.md](2026-07-08-macos-terminal-binding-plan.md) 的执行进度。

## 任务清单

- [x] 新增 `PCServer/attach/src/macos_terminal.rs`，定义 adapter trait 和 Terminal.app 实现
- [x] 实现 iTerm2 adapter
- [x] `PCServer/attach/src/session.rs` 新增 `terminal_id: Option<String>` 字段
- [x] `PCServer/attach/src/main.rs` 在 `attach track` 中检测 macOS 终端并获取 terminal_id
- [x] `PCServer/attach/src/service.rs` 接入 macOS adapter
- [x] 实现标签页识别并更新 session 元数据
- [x] 更新 `PCServer/attach/src/platform.rs` 能力声明
- [x] 添加单元测试和集成测试
- [x] 更新 `README.md`、验收文档、memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy --all-targets --all-features` 无新增 warning

## 后续待办事项

以下限制和增强项需要在后续迭代中继续处理：

- [x] 标签页切换同步：支持 Mobile 端展示可用标签页列表并允许主动选择（已完成）。
- [x] Terminal.app 输入转发改进：当前使用 `do script` 执行 `printf` 命令模拟输入，已替换为 `System Events` 发送真实按键，避免污染 shell 历史；无 Accessibility 权限时仍降级为 `do script`。
- [x] AppleScript 权限引导：`attach track` 与 `attach send-input` 时若 Terminal.app 未授权 Accessibility，会打印权限申请提示。
- [ ] 画面同步延迟优化：当前 `read-screen` 依赖轮询 `osascript`，后续应探索流式推送、增量更新或本地缓存机制（当前已实现 200ms 短期缓存，可降低高频轮询开销）。
- [x] 性能与稳定性压测：已完成 macOS 高频 read/send 压测，验证缓存稳定性与资源清理。
- [x] Terminal.app 窗口/标签页关闭检测：标签页关闭后，服务端会在下一次操作时清理对应 session。

## 当前状态

- 2026-07-08：完成 macOS Terminal.app / iTerm2 终端绑定基础实现。
- 2026-07-08：完成标签页切换同步，新增 `list-tabs` / `switch-tab` 协议请求、CLI 命令和服务端处理。
- 2026-07-08：完成 Terminal.app 真实按键输入与 `attach track` / `send-input` 时的 Accessibility 权限引导。
- 已补充 `docs/memory/features/2026-07-08-macos-terminal-binding.md`。
- 已记录上述待办限制。
