# 功能记忆：managed PTY 端到端测试

## 背景

- 需求来源：工程化中的“端到端集成测试”。
- 使用场景：单元测试覆盖模块逻辑，但需要验证真实 CLI、服务进程、token、managed PTY 操作能串起来。

## 关键功能点

- 新增 `PCServer/attach/tests/managed_pty_cli.rs`。
- 测试真实 `attach` 二进制。
- 覆盖 `hello`、`spawn-pty`、`send-input`、`read-screen`、`close`、`shutdown`。
- 使用临时端口和临时 auth 目录隔离环境。

## 设计与实现

- 涉及模块：`PCServer/attach/tests/managed_pty_cli.rs`。
- 核心流程：启动服务 → 创建 managed PTY → 写入输入 → 读取 screen → 关闭 session → 关闭服务。
- 重要约束：当前 E2E 覆盖 managed PTY，不覆盖普通 tracked daemon 的真实终端生命周期。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：集成测试和单元测试均通过。

## 后续注意事项

- CI 接入后应运行该测试，避免 CLI 协议回归。
