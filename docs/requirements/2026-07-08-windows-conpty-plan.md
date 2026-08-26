# Windows ConPTY managed PTY 实现计划

## 背景

- `PCServer/attach` 当前在 Unix（Linux/macOS）上已实现 managed PTY：可启动命令、写入输入、读取输出、调整窗口大小、关闭会话。
- Windows 平台仅在 `platform.rs` 中声明 `conpty_backend_not_implemented` 限制，`spawn-pty` / `read-screen` / `send-input` / `resize` 等操作返回 `unsupported_operation`。
- 为补齐跨平台能力，需要为 Windows 实现 ConPTY 后端。

## 目标

在 Windows 上实现与 Unix 对等的 managed PTY 能力：
- `attach spawn-pty "<command>"` 能启动命令并返回 session id。
- `attach read-screen <session-id>` 能读取当前 screen buffer。
- `attach send-input <session-id> "<input>"` 能写入输入。
- `attach resize <session-id> <cols> <rows>` 能调整窗口大小。
- `attach close <session-id>` 能停止子进程并清理会话。

## 方案

### 1. 依赖

- 引入 `portable-pty` 作为 Windows 依赖。该 crate 是 wezterm 项目的一部分， cross-platform 封装了 Windows ConPTY，API 稳定。
- 保留 Unix 现有 `nix` 实现，不做大改。

### 2. pty.rs 重构

- 将 `ManagedPty` 拆分为平台相关内部实现、统一公共 API：
  - `#[cfg(unix)]`：保留现有基于 `nix::pty::openpty` 的实现。
  - `#[cfg(windows)]`：基于 `portable_pty::{native_pty_system, CommandBuilder, PtySize}` 实现。
- 公共方法保持一致：
  - `spawn(command: &str, cols: u16, rows: u16) -> Result<Self>`
  - `send_input(&mut self, input: &str) -> Result<()>`
  - `resize(&self, cols: u16, rows: u16) -> Result<()>`
  - `child_id(&self) -> u32`
  - `is_exited(&mut self) -> bool`
  - `screen(&mut self) -> Result<String>`

### 3. Windows 实现细节

- 启动 PTY：
  - `native_pty_system().openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })`。
  - 使用 `CommandBuilder::new("cmd.exe")` 并传入 `/c` + 用户命令，保证与 Unix `/bin/sh -lc` 行为相近。
  - 后台线程持续从 `master.try_clone_reader()` 读取输出，写入 `Arc<Mutex<String>>` screen buffer。
- 写入输入：
  - 通过 `master.take_writer()` 获取的 writer 写入；writer 用 `Arc<Mutex>` 包装以适配 `&mut self` 接口。
- 调整大小：
  - 调用 `master.resize(PtySize { rows, cols, ... })`。
- 进程生命周期：
  - `child` 句柄保存用于 `try_wait` 和 `kill`。
  - `Drop` 中 kill + wait 子进程。
- screen buffer：
  - 复用 Unix 的 `trim_screen` 逻辑，限制最大 200KB。

### 4. service.rs 去平台限制

- 将 `ptys` 字段、相关方法从 `#[cfg(unix)]` 改为全平台可用。
- 删除 `#[cfg(not(unix))]` 的 `spawn_pty` / `read_screen` / `send_input` / `resize` stub。
- `spawn_pty` 中 Windows 使用 `cmd.exe /c` 包裹命令，Unix 保持 `/bin/sh -lc`。

### 5. platform.rs 能力声明

- Windows `windows-conpty` adapter：
  - `available: true`（运行时依赖 ConPTY，Windows 10 1809+ 默认支持）。
  - capabilities 增加 `managed_pty`、`metadata`、`tracked_terminal_io`。
  - limitations 移除 `conpty_backend_not_implemented`，保留 `requires_windows_10_1809_or_later`。

### 6. 测试

- 单元测试：
  - Windows 下复用 `captures_output_from_pty_command`、`writes_input_to_managed_pty`、`resizes_managed_pty`、`trims_screen_to_recent_output`。
  - 由于当前环境是 macOS，Windows 单元测试通过 `#[cfg(windows)]` 条件编译，使用 `cargo check --target x86_64-pc-windows-gnu` 验证编译。
- 集成测试：
  - `managed_pty_cli.rs` 中的测试目前依赖 Unix shell 命令，Windows 上无法直接运行；保持现状，后续在 Windows 环境补充。

### 7. 文档

- 更新 `README.md`：说明 Windows ConPTY 已支持。
- 更新 `docs/acceptance/pc-server-manual-acceptance.md`：增加 Windows 验收项或调整限制说明。
- 更新 `docs/memory/features/2026-07-07-managed-pty-send-input.md` 等相关 memory：记录 Windows 支持。
- 更新 `docs/memory/features/2026-07-07-unix-pty-backend-probe.md` 或新增 Windows memory。
- 更新 `docs/requirements/pc-mobile-api.md`：移除 Windows ConPTY 未实现的限制说明。
- 创建/更新进度文档。

## 验收标准

- `cargo test -p attach` 在当前 macOS 环境全部通过（Unix 路径不受影响）。
- `cargo clippy -p attach --all-targets --all-features` 无新增 warning。
- `cargo check -p attach --target x86_64-pc-windows-gnu` 编译通过（验证 Windows 代码编译）。
- `platform.rs` 中 Windows adapter 不再声明 `conpty_backend_not_implemented`。

## 风险

- `portable-pty` 在 Windows 上依赖 ConPTY，Windows 10 1809 以下版本不支持；需在 limitations 中声明。
- 当前无 Windows 运行环境，无法实际执行 Windows 集成测试；仅能验证编译和逻辑。
- `cmd.exe /c` 与 `/bin/sh -lc` 在引号、环境变量等方面有差异，可能需要后续微调。
