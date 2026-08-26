# 功能记忆：Unix PTY 基础验证

## 背景

- 需求来源：PC 服务端六大块进度中的“核心终端能力”。
- 使用场景：后续 `read_screen`、`send_input`、`resize` 需要真实 PTY 能力，先验证 Rust 侧可以创建 PTY 并读取命令输出。

## 关键功能点

- 新增 `pty` 模块；Unix 侧通过 `nix::pty::openpty` 创建 master/slave，Windows 侧通过 `portable-pty` 调用 ConPTY。
- 可在 slave/ConPTY 侧启动 shell 命令，并从 master 侧捕获输出。
- `ManagedPty` 公共 API 跨平台一致：`spawn`、`send_input`、`resize`、`child_id`、`is_exited`、`screen`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`、`PCServer/attach/src/main.rs`、`PCServer/attach/Cargo.toml`。
- 核心流程：openpty → slave 作为子进程 stdio → master 读取输出 → child 退出后回收。
- 重要约束：Unix 与 Windows 内部实现不同，但公共 API 一致；Windows 依赖 ConPTY，仅支持 Windows 10 1809+。

## 验证方式

- 命令：`cargo test -p attach captures_output_from_pty_command`
- 命令：`cargo test -p attach`
- 结果：单元测试通过，PTY 输出包含 `attach-pty-ok`。

## 后续注意事项

- 接入真实 session 时需要持有 PTY master，并设计非阻塞读取和输入写入。
- Windows 需要单独实现 ConPTY，不能复用 Unix PTY 模块。
