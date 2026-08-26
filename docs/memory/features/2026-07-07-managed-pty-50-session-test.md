# 功能记忆：50 managed PTY 会话压力测试

## 背景

- 需求来源：稳定性与性能中的“40~50 终端压力测试”。
- 使用场景：目标场景要求同时管理大量终端，会话列表至少要能稳定承载 50 个 managed PTY session。

## 关键功能点

- 集成测试创建 50 个 managed PTY session。
- 通过 `attach list` 校验返回 50 个 `managed_pty` 会话。
- 测试使用临时端口和临时 auth 目录。

## 设计与实现

- 涉及模块：`PCServer/attach/tests/managed_pty_cli.rs`。
- 核心流程：循环 `spawn-pty` → `list` → 统计 `managed_pty` 数量 → `shutdown`。
- 重要约束：当前压力测试覆盖 managed PTY 列表能力，不代表普通 OS 终端 track 场景已完成。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：集成测试通过，可列出 50 个 managed PTY 会话。

## 后续注意事项

- 后续需要补资源占用监控和普通 tracked 终端压力验证。
