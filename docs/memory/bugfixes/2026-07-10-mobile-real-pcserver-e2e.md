# BugFix 记忆：移动端真实 PCServer E2E 阻断

## 现象

- 触发条件：iOS、Android、HarmonyOS 客户端连接宿主机真实 attach PCServer，尝试列出会话、读屏和发送输入。
- 用户影响：移动端只能进入基础界面，无法稳定证明真实终端会话可用。

## 根因

- 移动端之前通过 `register tracked` 和 `list_windows` 走伪会话路径，不能直接操作 PCServer 已存在的 managed pty session。
- 服务器配置持久化没有保存 attach token，重启 App 后无法连接需要鉴权的 PCServer。
- HarmonyOS 缺少 `ohos.permission.INTERNET`，导致 native socket 创建失败。
- Android 侧已知问题为缺少 `android.permission.INTERNET` 且主线程执行网络请求；已在前置修复中处理。
- iOS native TCP 曾因 IPv4 字节序错误无法连通宿主机；已在前置修复中处理。

## 修复方案

- 涉及模块：
  - `MobileClient/remote-control-shared`
  - `MobileClient/composeUI`
  - `MobileClient/harmonyApp`
- 关键改动：
  - 移动端改为请求 `list_sessions`，将每个 PCServer session 映射为一个窗口和一个 tab。
  - 读屏、输入、resize 直接使用真实 session id。
  - 配置编码新增 token 字段，并兼容旧 6 字段配置。
  - 服务器编辑弹窗新增 token 输入项。
  - HarmonyOS `module.json5` 新增 `ohos.permission.INTERNET`。

## 验证方式

- 复现步骤：
  - 启动 PCServer `0.0.0.0:48740`。
  - 创建 `cat` managed pty session 并写入标记文本。
  - 三端客户端配置宿主机地址、端口和 token 后进入终端。
- 验证命令：
  - `cd MobileClient && ./gradlew :remote-control-shared:test --console=plain`
  - `cd MobileClient && ./gradlew :androidApp:assembleDebug --console=plain`
  - `cd MobileClient && ./gradlew :composeUI:linkDebugFrameworkIosSimulatorArm64 --console=plain`
  - `cd MobileClient/harmonyApp && devecocli build`
- 验证结果：
  - iOS：连接、会话列表、读屏、发送输入通过。
  - HarmonyOS：连接、会话列表、读屏通过；输入自动化未触发发送，仍需后续修复。
  - Android：构建和基础启动通过；真实 E2E 被 ADB/emulator 环境阻塞。

## 预防措施

- 移动端协议测试必须覆盖 `list_sessions` 响应解析，避免回退到伪 tracked session。
- 端到端报告不能把“进入界面”当作“真实终端可用”，必须保留 PCServer 日志或读屏截图。
- HarmonyOS 网络能力变更时必须复查 `module.json5` 权限声明。
