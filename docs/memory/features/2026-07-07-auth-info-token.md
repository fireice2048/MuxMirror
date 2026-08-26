# 功能记忆：auth-info 与 token 校验

## 背景

- 需求来源：PC 服务端六大块进度中的“安全与连接”。
- 使用场景：Mobile App 通过 SSH 登录电脑后，执行 `attach auth-info` 获取本机 Attach 服务 endpoint 和 token，再用 token 调用 Attach 协议。

## 关键功能点

- 新增 `attach auth-info` 命令，输出 `protocol_version`、`endpoint`、`token`、`user`。
- token 保存在当前用户私有目录 `~/.attach/token`。
- 服务端协议入口改为解析 `AuthenticatedRequest`，所有请求必须携带匹配 token。
- token 错误时统一返回 `unauthorized attach request`。

## 设计与实现

- 涉及模块：`PCServer/attach/src/auth.rs`、`PCServer/attach/src/protocol.rs`、`PCServer/attach/src/service.rs`、`PCServer/attach/src/main.rs`。
- 核心流程：服务启动时加载或创建 token → CLI 请求由 `send_request` 自动包上 token → 服务端在唯一请求入口校验 token → 校验通过后处理原有 `ClientRequest`。
- 重要约束：当前仍使用 TCP 本机端口；后续如切换 Unix Domain Socket 或 Windows Named Pipe，应复用同一 token 校验语义。

## 验证方式

- 命令：`cargo test -p attach`
- 命令：临时 `ATTACH_AUTH_DIR` 和 `ATTACH_SERVICE_ADDR` 下执行 `target/debug/attach auth-info`、`target/debug/attach list`、`target/debug/attach shutdown`
- 结果：单元测试通过；CLI 冒烟输出包含 endpoint/token/user，list 和 shutdown 可通过 token 校验。

## 后续注意事项

- Mobile 正式 API、协议版本/能力查询和错误码还未实现。
- 后续新增读取终端画面、输入转发、resize 等请求时必须继续走 `AuthenticatedRequest`。
