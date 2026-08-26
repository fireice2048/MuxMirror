# 标签页切换同步实现进度

本文跟踪 [2026-07-08-tab-switching-plan.md](2026-07-08-tab-switching-plan.md) 的执行进度。

## 任务清单

- [x] `protocol.rs` 新增 `ListTabs` / `SwitchTab` 请求与响应
- [x] `macos_terminal.rs` `TabInfo` 支持序列化
- [x] `service.rs` 实现 `list_tabs` / `switch_tab`
- [x] `main.rs` 新增 `list-tabs` / `switch-tab` CLI 命令
- [x] `platform.rs` 更新能力声明
- [x] 补充单元测试与集成测试
- [x] 更新 `README.md`、验收文档、memory
- [x] `cargo test -p attach` 全部通过
- [x] `cargo clippy --all-targets --all-features` 无新增 warning

## 当前状态

- 全部任务已完成，代码已验证。

## 变更记录

- 2026-07-08：创建本进度文档。
- 2026-07-08：完成标签页切换同步实现并更新本文。
