# 功能记忆：PCServer 持久化日志

## 背景

- PCServer 原有 `tracing` 日志仅输出终端，缺少本地文件留存、按日滚动和保留期清理。
- CLI 的标准输出承载 JSON 和会话 ID 协议，诊断日志不能混入标准输出。

## 关键结论

- `PCServer/attach/src/logging.rs` 使用 `tracing_subscriber` 自定义 writer，将日志以 FIFO 队列交给后台线程处理；主业务线程不直接写日志文件。
- 后台线程最多合并两秒内的日志后写入终端标准错误和 `~/.attach/logs/attach-YYYY-MM-DD.log`，按本地日期滚动并保留最近 30 天。
- 启动和日志滚动均输出 App、版本、操作系统信息 Banner；日志行带本地时间戳和 `[E]`、`[W]`、`[I]`、`[D]`、`[T]` 级别。
- 继续使用 `RUST_LOG` 控制过滤级别；结构化字段和现有 `tracing` 调用不变。

## 影响范围

- 仅影响 `PCServer/attach` 的日志初始化和 `time` 时间处理依赖。
- CLI JSON 和会话 ID 仍只写入标准输出；终端诊断日志写入标准错误。
- 移动端日志桥接保持不变。

## 验证方式

- `cargo test -p attach`
- `cargo clippy --all-targets --all-features`
- 使用独立 HOME 执行 `RUST_LOG=debug target/debug/attach hello`，确认标准错误和按日日志文件中均含 Banner 与格式化日志。
