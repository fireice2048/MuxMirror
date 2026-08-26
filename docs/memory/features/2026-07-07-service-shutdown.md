# 功能记忆：Attach 服务优雅关闭

## 背景

- 需求来源：服务端验收后需要清理测试服务，避免残留 `attach service` 进程。
- 使用场景：开发者执行人工验收或临时端口测试后，可以通过命令请求服务退出。

## 关键功能点

- 新增 `attach shutdown` 命令。
- 服务收到 `Shutdown` 请求后返回 `ShuttingDown`。
- 服务主循环在处理完当前请求后退出。

## 设计与实现

- 涉及模块：`PCServer/attach/src/main.rs`、`PCServer/attach/src/service.rs`。
- 核心流程：CLI 发送 `ClientRequest::Shutdown` → 服务状态标记 `shutting_down` → 响应 `ServerResponse::ShuttingDown` → accept 循环退出。
- 重要约束：当前只关闭服务进程，不会主动停止已启动的 `attach daemon`；后续需要补充 daemon 生命周期管理。

## 验证方式

- 命令：`cargo clippy --all-targets --all-features -- -D warnings`
- 命令：`cargo test -p attach`
- 命令：`ATTACH_SERVICE_ADDR=127.0.0.1:48742 target/debug/attach list && ATTACH_SERVICE_ADDR=127.0.0.1:48742 target/debug/attach shutdown`
- 结果：clippy 通过，7 个单元测试通过，shutdown 后端口不再监听。

## 后续注意事项

- 需要补充服务退出时通知或清理 daemon 的机制。
- 需要完善 shutdown 的权限控制，避免非授权客户端关闭服务。
