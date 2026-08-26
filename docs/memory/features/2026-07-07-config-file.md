# 功能记忆：配置文件

## 背景

- 需求来源：工程化中的“配置文件”。
- 使用场景：用户不想每次设置 `ATTACH_SERVICE_ADDR`，可通过固定配置文件设置服务地址。

## 关键功能点

- 默认读取 `~/.attach/config.json`。
- 可通过 `ATTACH_CONFIG` 指定配置文件路径。
- 当前支持 `service_addr`。
- `ATTACH_SERVICE_ADDR` 环境变量优先级高于配置文件。

## 设计与实现

- 涉及模块：`PCServer/attach/src/config.rs`、`PCServer/attach/src/endpoint.rs`。
- 核心流程：endpoint 先读 env → 没有 env 时读 config → 都没有时使用默认 `127.0.0.1:47631`。
- 重要约束：当前配置只覆盖服务地址，不引入完整配置管理。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_CONFIG` 下执行 `attach hello` 和 `attach shutdown`
- 结果：单元测试通过；CLI 冒烟使用配置文件端口正常启动服务。

## 后续注意事项

- 后续新增配置项时保持 env 优先，避免破坏现有脚本。
