# BugFix 记忆：iOS native TCP IPv4 字节序错误

## 现象

- 触发条件：iOS Simulator 中移动端 App 使用 `127.0.0.1:48740` 连接本机 PCServer 测试服务。
- 用户影响：App 点击服务器后停留在“加载终端窗口…”，日志只有 `request to 127.0.0.1:48740`，没有 `TcpConnection connected`，无法完成 `list_sessions`。

## 根因

- `TcpConnection.native.kt` 手写 IPv4 地址解析时按大端数值累加 `127.0.0.1`，直接赋给 `sockaddr_in.sin_addr.s_addr`。
- iOS/macOS native socket 结构需要网络字节序；在 little-endian 机器上写入错误字节序会导致 `connect()` 连接到错误地址并阻塞。

## 修复方案

- 涉及模块：`MobileClient/remote-control-shared/src/nativeMain/kotlin/com/attach/mobile/remotecontrol/TcpConnection.native.kt`
- 关键改动：将 IPv4 解析改为按 `sin_addr.s_addr` 所需字节序组装，并校验必须是合法 dotted IPv4 地址。

## 验证方式

- 复现步骤：预置 `Local PCServer`，创建 managed PTY，iOS App 打开服务器并进入 session。
- 验证命令：
  - `./gradlew :composeUI:linkDebugFrameworkIosSimulatorArm64 --console=plain`
  - `xcodebuild -project MobileClient/iosApp/iosApp.xcodeproj -scheme iosApp -configuration Debug -destination 'platform=iOS Simulator,id=E067BA29-6871-4670-A343-D3446EEFB13A' -derivedDataPath MobileClient/iosApp/build/DerivedData build`
  - `xcodebuild -project docs/acceptance/evidence/ios/ui-test-harness/AttachMobileE2E.xcodeproj -scheme AttachMobileE2EUITests -destination 'platform=iOS Simulator,id=E067BA29-6871-4670-A343-D3446EEFB13A' -derivedDataPath docs/acceptance/evidence/ios/ui-test-harness/build/DerivedData test-without-building`
- 验证结果：App 日志出现 `connected to 127.0.0.1:48740`、`loaded 1 sessions`、`input accepted`，服务端 `read-screen` 可见 `mobile-e2e-ready` 和 `ios-mobile-e2e-ok`。

## 预防措施

- native socket 地址字段不要手写主机字节序整数后直接赋值；若必须手写解析，应明确目标字段的字节序并用真机/模拟器端到端验证。
