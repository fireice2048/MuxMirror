# 功能记忆：HarmonyOS 标准 SSH 直连终端

## 背景

- 需求来源：移动端点击服务器列表项后直接进入终端，不再经过 Attach 自定义 TCP/JSON 协议和窗口列表。
- 使用场景：HarmonyOS 手机或模拟器通过标准 SSH 连接电脑，显示 Loading 后打开交互式 PTY shell。

## 关键功能点

- 共享 Compose 页面负责 Loading、输出画布、输入栏、快捷键和失败返回。
- HarmonyOS 平台使用 libssh2 1.11.1，使用 mbedTLS 3.6.3 作为加密后端。
- 连接使用服务器配置中的 IPv4、端口、用户名和密码；日志不得记录密码。
- 成功认证后请求 `xterm-256color` PTY，channel 使用非阻塞轮询读写。
- TCP 建连使用 10 秒非阻塞连接超时，不依赖协程取消中断原生阻塞调用。

## 设计与实现

- 涉及模块：`MobileClient/composeUI`、`MobileClient/harmonyApp/scripts`。
- 核心流程：列表点击 → Loading → TCP connect → SSH handshake → password auth → session channel → PTY → shell → 终端读写。
- 重要约束：首版 HarmonyOS 只支持 IPv4 和密码认证；主机密钥持久化与公钥认证留待后续增强。Android/iOS 保持平台实现可替换，但本阶段仍显示未实现提示。

## 验证方式

- 命令：强制重链 arm64-v8a/x86_64 共享库，清理 `harmonyApp/entry/build`，重打并安装 HAP。
- 结果：模拟器已完成 TCP 与 SSH 握手且应用无崩溃；当前保存口令被本机 SSH 服务拒绝，密码认证、PTY 和输入仍需有效凭据完成验收。

## 后续注意事项

- 模拟器应连接开发机当前局域网 IPv4；DHCP 地址可能变化，不要把验收地址硬编码。
- KMM 共享库变化后必须先发布二进制，再清理鸿蒙构建目录，否则 HAP 可能继续打包旧 `libkn.so`。
- 增加主机密钥校验、公钥认证或域名解析时，应先更新需求和安全边界。
