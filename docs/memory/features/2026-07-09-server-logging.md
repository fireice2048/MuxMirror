# 功能记忆：服务端结构化日志补全

## 背景

- 需求来源：用户要求为 PCServer 服务端补充日志系统，遵循全局日志规范，便于后续运维与移动端联调排错。
- 使用场景：服务启动、CLI 调用、session 注册/心跳/过期、PTY 创建与回收、终端窗口/标签页查询、鉴权 token 加载等关键路径。

## 关键功能点

- 统一使用 `tracing` 记录结构化日志，按级别区分：
  - `trace`：高频细节（已省略，避免日志爆炸）
  - `debug`：诊断信息（请求入口、参数、适配器选择、TTY 检测等）
  - `info`：生命周期里程碑（服务启动、session 注册/过期/关闭、PTY spawn、子进程退出）
  - `warn`：可恢复异常（鉴权失败、空 token、osascript 失败、未知请求类型）
  - `error`：操作失败（服务拉起失败、PTY 子进程异常退出、TTY 读取失败）
- 不记录敏感信息：token 本身通过 `AuthenticatedRequest` 的自定义 `Debug` 做脱敏，日志中不打印完整 token。
- 保留必要的 CLI 输出：`main.rs` 中各子命令的 JSON 结果通过 `println!` 输出，属于协议/用户输出，不视为诊断日志。
- 测试中的跳过提示使用 `eprintln!`，仅在测试场景出现，符合规范。

## 设计与实现

- 涉及模块：
  - `PCServer/attach/src/service.rs`：请求分发、session 生命周期、窗口/标签页查询、PTY 操作。
  - `PCServer/attach/src/auth.rs`：token 加载、创建、重试、校验。
  - `PCServer/attach/src/main.rs`：CLI 入口、服务自动拉起。
  - `PCServer/attach/src/macos_terminal.rs`：macOS Terminal/iTerm2 adapter 选择、AppleScript 执行。
  - `PCServer/attach/src/pty.rs`：managed PTY 创建、读取、回收。
  - `PCServer/attach/src/tracked_tty.rs`：TTY 检测与读取。
- 核心流程：
  1. 在请求入口按请求类型记录 `debug`，失败时记录 `warn` 并附带错误码。
  2. session 注册、心跳刷新、过期清理、关闭时记录 `info`/`warn`，包含 `session_id`、`terminal_key`、`session_kind`。
  3. `spawn_pty` 成功/失败记录 `info`/`error`，包含尺寸与命令。
  4. macOS adapter 选择失败记录 `warn`，PTY 子进程退出记录 `info`/`error`。
  5. token 加载/创建路径记录 `info`，重试与空 token 记录 `warn`。
- 重要约束：
  - 不要因日志引入阻塞 I/O 或影响主循环响应。
  - 不记录密钥、token、密码；`AuthenticatedRequest` 的 Debug 已做脱敏。
  - 保持最小改动，不重构业务逻辑。

## 验证方式

- 命令：
  ```bash
  cd PCServer/attach
  cargo fmt --all
  cargo clippy --all-targets --all-features
  cargo test -p attach
  ```
- 结果：
  - `cargo fmt --all` 无变更。
  - `cargo clippy --all-targets --all-features` 通过，无警告。
  - `cargo test -p attach` 全部通过：69 个单元测试 + 5 个 managed PTY CLI 集成测试 + 1 个 tracked terminal CLI 集成测试。

## 后续注意事项

- 后续新增服务端行为时，应同步补充对应日志；新增错误路径必须记录日志，避免排错盲区。
- 当日志量过大时，可考虑按模块或请求类型添加 `RUST_LOG` 过滤，避免影响生产性能。
- 移动端日志系统待后续按同样规范补充。
