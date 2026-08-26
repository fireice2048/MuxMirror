# 功能记忆：Windows ConPTY managed PTY

## 背景

- `PCServer/attach` 的 managed PTY 能力此前仅在 Unix（Linux/macOS）上实现，Windows 平台在 `platform.rs` 中声明 `conpty_backend_not_implemented`。
- 为补齐跨平台能力，需要为 Windows 提供 ConPTY 后端，使 `spawn-pty` / `read-screen` / `send-input` / `resize` / `close` 在 Windows 上可用。

## 关键功能点

- 引入 `portable-pty` 作为 Windows 依赖，该 crate 是 wezterm 项目的一部分，统一封装了 ConPTY API。
- `PCServer/attach/src/pty.rs` 拆分为 `unix` / `windows` 两个子模块，对外暴露统一的 `ManagedPty` API。
- Windows 实现使用 `NativePtySystem::default()` 打开 ConPTY，启动 `cmd.exe /c` 包裹用户命令。
- 后台线程持续从 PTY reader 读取输出，写入 `Arc<Mutex<String>>` screen buffer；`send_input` 通过 writer 写入；`resize` 调用 `MasterPty::resize`。
- `service.rs` 中 pty 相关字段与方法不再受 `#[cfg(unix)]` 限制，`spawn_pty` 根据平台选择 `/bin/sh -lc` 或 `cmd.exe /c`。
- `platform.rs` 中 `windows-conpty` adapter 标记为 `available: true`，capabilities 增加 `managed_pty`，limitations 改为 `requires_windows_10_1809_or_later`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/platform.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/Cargo.toml`。
- 核心流程：
  1. CLI 发送 `spawn_pty` 请求。
  2. `service.rs` 调用 `ManagedPty::spawn`。
  3. Windows 侧通过 `portable-pty` 创建 ConPTY 并启动 `cmd.exe /c <command>`。
  4. 后台线程读取输出到 screen buffer。
  5. `read_screen` / `send_input` / `resize` / `close` 与 Unix 路径共用同一 `ServiceState` 逻辑。
- 重要约束：
  - Windows 依赖 ConPTY，仅支持 Windows 10 1809 及更高版本。
  - 当前开发环境为 macOS，Windows 代码通过 `cargo check --target x86_64-pc-windows-gnu` 验证编译，实际运行测试需在 Windows 环境补做。
  - `cmd.exe /c` 与 `/bin/sh -lc` 在引号、转义、环境变量等方面存在差异，后续可根据实际使用反馈微调。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：60 个单元测试 + 3 个 managed PTY 集成测试 + 1 个 tracked terminal 集成测试全部通过（Unix 路径未受影响）。
- 命令：`cargo check -p attach --target x86_64-pc-windows-gnu`
- 结果：Windows 代码编译通过。
- 命令：`cargo clippy -p attach --all-targets --all-features`
- 结果：无新增 warning。

## 后续注意事项

- 在真实 Windows 环境中运行 `managed_pty_cli.rs` 集成测试，确认 `cmd.exe /c echo`、长期 `cmd.exe` 会话的输入/输出/关闭行为。
- 评估是否需要为 Windows 提供 PowerShell 或 WSL 命令包裹选项。
- 后续如统一 Unix/Windows PTY 实现，可考虑完全迁移到 `portable-pty`，但当前保留 Unix `nix` 实现以最小化变更。
