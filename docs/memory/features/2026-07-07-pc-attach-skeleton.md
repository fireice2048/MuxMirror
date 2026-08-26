# 功能记忆：PC Attach 最小开发骨架

## 背景

- 需求来源：用户要求提交文档后开始开发。
- 使用场景：先建立可运行的 Rust PC 端基础，为后续终端会话跟踪、手机查询和操作能力打基础。

## 关键功能点

- 新增 Cargo workspace，当前成员为 `PCServer/attach`。
- 新增 `attach` CLI，默认执行 `register`。
- `attach register` 自动启动本机单例服务，并注册当前终端会话。
- `attach service` 在前台运行 Attach 服务。
- `attach list` 查询并输出已注册会话 JSON。
- 当前服务原型使用 loopback TCP 地址 `127.0.0.1:47631`，支持通过 `ATTACH_SERVICE_ADDR` 覆盖。

## 设计与实现

- 涉及模块：`PCServer/attach/src/main.rs`、`service.rs`、`protocol.rs`、`session.rs`、`endpoint.rs`。
- 核心流程：CLI 检测服务可用性 → 不可用时拉起服务 → 通过 JSON 行协议注册/查询会话。
- 重要约束：当前仅为本机原型；终端画面同步、输入转发、标签页识别尚未实现。

## 验证方式

- 命令：`cargo clippy --all-targets --all-features -- -D warnings`
- 命令：`cargo test -p attach`
- 命令：`ATTACH_SERVICE_ADDR=127.0.0.1:48731 cargo run -p attach -- register && ATTACH_SERVICE_ADDR=127.0.0.1:48731 cargo run -p attach -- list`
- 结果：clippy 通过，3 个单元测试通过，CLI 冒烟可注册并列出当前终端会话。

## 后续注意事项

- 需要设计 SSH 登录后的服务发现与授权方式。
- 需要评估 loopback TCP、Unix socket、Windows named pipe 在跨平台场景下的最终取舍。
- 需要补充服务后台生命周期管理和过期会话清理。
