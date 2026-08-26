# 功能记忆：重复 track 去重

## 背景

- 需求来源：服务端稳定性与性能块中的“重复 track 去重”。
- 使用场景：用户可能在同一个终端多次执行 `attach` 或把 `attach` 放入 shell 启动脚本，服务端不应为同一终端无限累积会话。

## 关键功能点

- `TerminalSession` 新增 `terminal_key` 字段。
- `attach track` 启动后台 `daemon` 时，将父进程计算出的 `terminal_key` 通过环境变量 `ATTACH_TERMINAL_KEY` 传给 daemon。
- 服务注册会话时按 `terminal_key` 移除旧会话，只保留最新会话。

## 设计与实现

- 涉及模块：`PCServer/attach/src/main.rs`、`PCServer/attach/src/session.rs`、`PCServer/attach/src/service.rs`。
- 核心流程：父进程计算当前终端 key → daemon 继承 key → 注册请求携带 key → 服务按 key 替换旧会话。
- 重要约束：当前 `terminal_key` 主要基于父进程 PID 或显式环境变量，后续需要替换为更可靠的真实终端/PTY 标识。

## 验证方式

- 命令：`cargo test -p attach service::tests::registering_same_terminal_key_replaces_existing_session`
- 命令：`cargo test -p attach session::tests::terminal_key_can_be_overridden_from_environment`
- 命令：`cargo test -p attach`
- 命令：同一临时端口连续执行两次 `target/debug/attach track` 后执行 `target/debug/attach list`
- 结果：单元测试通过；CLI 冒烟中同一终端只保留一条会话。

## 后续注意事项

- 需要用真实终端/PTY 标识替代当前父进程 PID 推导方式。
- 需要清理被替换的旧 daemon，避免旧 daemon 继续心跳失败后残留到 TTL 过期。
