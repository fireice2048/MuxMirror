# 普通被跟踪终端 I/O 实现计划

## 背景

- 当前 managed PTY 路径已完整支持 `read_screen` / `send_input` / `resize`。
- 普通 `tracked` session 的 `read_screen` / `send_input` / `resize` 仍返回 `unsupported_operation`。
- `docs/requirements/pc-server-progress.md` 六大板块完成后，下一步建议进入 Mobile 端联调或实现普通被跟踪 OS 终端的真实画面/输入绑定。
- Mobile 端联调需要至少一条可用的终端会话 I/O 路径；managed PTY 已可用，但真实被跟踪终端仍不可用。

## 目标

为 Unix/Linux 平台上的普通被跟踪终端实现基础的画面同步和输入转发能力。macOS 作为实验性支持，通过 TTY 检测在可行时启用，不可行时保持 `unsupported_operation` 降级。

## 技术方案

1. **TTY/PTS 检测**
   - daemon 在注册 tracked session 时，检测被跟踪进程的控制终端设备路径。
   - Linux：通过读取 `/proc/<pid>/fd/0` 的符号链接获取 pts 路径。
   - macOS/Unix：通过 `ttyname` 或 `TIOCGPGRP` 等 ioctl 获取。
2. **TTY 绑定**
   - 服务为每个带有 `tty_path` 的 tracked session 维护一个 `TrackedTerminal` 句柄。
   - 打开设备文件进行非阻塞读取和写入，并维护最近输出缓冲。
3. **画面同步**
   - `read_screen` 从 TTY 主设备读取最近的输出缓冲返回给客户端。
4. **输入转发**
   - `send_input` 向 TTY 主设备写入输入。
5. **窗口大小同步**
   - `resize` 通过 `TIOCSWINSZ` ioctl 调整 TTY 窗口大小，并更新 session 元数据。

## 任务拆分

1. 新增 `PCServer/attach/src/tracked_tty.rs` 模块，封装 TTY 检测、打开、读写、resize 和 screen buffer。
2. `PCServer/attach/src/session.rs` 增加 `tty_path: Option<String>` 字段。
3. `PCServer/attach/src/main.rs` 的 `track_current_terminal` 在注册前检测并设置 `tty_path`。
4. `PCServer/attach/src/service.rs` 为 tracked session 维护 `tracked_ttys`，在 `read_screen` / `send_input` / `resize` 中优先尝试 tracked session 绑定。
5. `PCServer/attach/src/platform.rs` 更新 `supports_tracked_terminal_io` 能力声明。
6. `PCServer/attach/src/protocol.rs` 在 capabilities 中添加 `tracked_terminal_io`。
7. 添加单元测试和集成测试。
8. 更新 `README.md` 和验收文档，说明 tracked terminal I/O 的当前限制。

## 风险与约束

- 读取其他进程的 PTY 主设备需要同一用户权限；权限不足时返回 `unsupported_operation`。
- 多个读取者竞争 TTY 输出；当前阶段以"能读到就展示"为准，不要求完全独占。
- macOS 上 `/dev/tty*` 权限较严格，可能只能检测而无法读写。
- 此实现为原型阶段的"最佳努力"方案，后续可考虑 PTY 包装模式或终端模拟器特定 API。

## 验收标准

- `cargo test -p attach` 全部通过。
- 新增集成测试：启动子 shell 在 pts 中运行，通过 `attach read-screen` / `send-input` 验证 tracked session I/O。
- `attach status` 在 Linux 上报告 `supports_tracked_terminal_io: true`。
- 权限不足时返回 `unsupported_operation` 而不是 panic 或内部错误码。
