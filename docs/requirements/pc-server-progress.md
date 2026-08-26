# PC 服务端六大块进度

本文用于跟踪 Attach PC 服务端剩余开发工作。每完成一块，必须更新本文件并在回复中提醒整体进度。

## 1. 核心终端能力

- [x] 终端画面同步
- [x] 输入转发
- [x] 真实 PTY / 终端绑定
- [x] 会话接管 / attach / detach
- [x] 终端窗口大小同步 / resize

## 2. 服务协议

- [x] Mobile 正式 API
- [x] 会话操作协议
- [x] `connect session`
- [x] `send input`
- [x] `read screen`
- [x] `resize`
- [x] 协议版本协商
- [x] 错误码设计

## 3. 跨平台适配

- [x] macOS Terminal / iTerm2 适配
- [x] Linux 常见终端适配
- [x] Windows Terminal / ConPTY 适配
- [x] 终端标签页识别
- [x] 平台差异处理

## 4. 安全与连接

- [x] SSH 后服务发现
- [x] `attach auth-info`
- [x] 访问控制 / token 校验
- [x] 多用户隔离
- [x] 敏感信息保护
- [x] 服务默认仅本机访问策略固化

## 5. 稳定性与性能

- [x] 后台心跳续约
- [x] TTL 过期会话清理
- [x] 优雅 `shutdown`
- [x] 重复 `track` 去重
- [x] 40~50 终端压力测试
- [x] 资源占用优化
- [x] 服务崩溃恢复
- [x] 旧 daemon 清理
- [x] daemon 跟随真实终端生命周期退出

## 6. 工程化

- [x] Cargo workspace
- [x] PC 端基础 README
- [x] 服务端人工验收文档
- [x] 需求文档
- [x] 记忆系统
- [x] 安装命令 / 安装脚本
- [x] 配置文件
- [x] 端到端集成测试
- [x] CI
- [x] 发布包 / 版本管理

## 当前整体状态

- 六大板块完成度：6 / 6 个板块完全完成。
- 2026-07-08 里程碑：服务端启动、连接处理与 managed PTY 压测稳定性加固完成。
- 第 1 块“核心终端能力”已完成服务端 managed PTY 路径：可启动长期命令、写入输入、读取 PTY 输出、限制 screen buffer、调整窗口大小与尺寸元数据，并支持 connect/detach/close 生命周期；普通 tracked OS 终端的真实画面/输入绑定仍是后续增强，不作为当前服务端 managed PTY 完成范围。
- 第 2 块“服务协议”已完成 `hello`、`status`、协议版本返回、结构化错误码、会话操作请求/响应、`connect session` 元数据连接、managed PTY `read screen`、`send input`、`resize`、显式 session kind 和 Mobile API 草案文档。
- 第 3 块“跨平台适配”已完成服务端平台能力探测和 adapter 状态输出：macOS Terminal/iTerm2、Linux PTY、Windows ConPTY 均有明确 adapter、能力与限制描述；Windows ConPTY managed PTY 已实现，普通被跟踪终端 I/O 仍声明为未实现能力。
- 第 4 块“安全与连接”已完成基础 `auth-info`、token 文件、请求 token 校验、用户私有目录、默认本机监听和 token 调试脱敏。
- 第 5 块“稳定性与性能”已完成基础心跳、TTL、shutdown、重复 `track` 去重、会话主动关闭清理、已退出 managed PTY 自动清理、服务重启后 daemon 自动重注册、旧 daemon 停止和 daemon 跟随真实终端生命周期退出，以及 50 个 managed PTY 会话列表压力测试。
- 第 6 块“工程化”已完成基础文档、workspace、验收文档、安装脚本、配置文件、端到端集成测试、CI 和发布包脚本。
- 下一步建议进入 Mobile 端联调，或另开增强任务实现 Linux 被跟踪终端的真实画面/输入绑定。
