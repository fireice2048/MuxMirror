# 功能记忆：移动端多平台日志桥接

## 背景

- 需求来源：用户要求移动端拥有自己的日志系统，且遵循全局日志规范。
- 使用场景：Android、iOS、HarmonyOS 三端共用 `remote-control-shared` 业务逻辑，需要统一日志门面，由**各平台 App 工程**注入具体实现，避免平台代码混入跨平台 UI 层（`composeUI`）。

## 关键功能点

- `remote-control-shared` 只定义日志接口与门面，不耦合任何平台日志 API：
  - `LogLevel`：VERBOSE / DEBUG / INFO / WARN / ERROR。
  - `LogWriter`：平台需实现此接口。
  - `AttachLog`：全局日志门面，通过 [setLogWriter] 注入实现；未注入时静默丢弃，不影响业务。
- 平台实现放在**各平台 App 工程**：
  - **Android**：`androidApp` 提供 `AndroidLogWriter`，使用 `android.util.Log`。
  - **iOS**：`iosApp` 用 Swift 实现 `ComposeLogWriter`（由 `composeUI` 导出），调用 `NSLog`。
  - **HarmonyOS**：`harmonyApp` 的 C++ NAPI 层实现 `OH_LOG_Print` 回调；`composeUI/ohosMain` 仅保留回调注册与调用的薄桥接。
- `composeUI` 跨平台代码不实现具体日志后端，但为 iOS 提供 Swift 可见的薄桥接：
  - `ComposeLogWriter`：Swift 可实现的协议。
  - `ComposeLogBridge.setLogWriter(...)`：将 Swift 写入器转接到 `AttachLog`。
- 初始化位置：
  - Android：`MainActivity.onCreate` 调用 `AttachLog.setLogWriter(AndroidLogWriter())`。
  - iOS：`iOSApp.init` 调用 `ComposeLogBridge.shared.setLogWriter(writer: IOSLogWriter())`。
  - HarmonyOS：`harmonyApp/entry/src/main/cpp/napi_init.cpp` 的 `Init` 中注册回调并调用 `InitializeAttachLogging()`。
- 已补充关键路径日志：
  - `TcpTerminalClient`：请求目标、会话注册、窗口/标签页加载、读屏、输入、尺寸调整、切换标签页及错误。
  - `TcpConnection`（Android/Native）：连接、读写失败。
  - `App.kt`：服务器打开、窗口列表加载、读屏/输入失败、服务器配置存取。
  - `ServerConfigStore` 各平台实现：加载/保存长度与失败。
- 不记录敏感信息：日志中不出现 token、密码；仅记录服务器名、地址、端口、窗口/标签页标题、数据长度等。

## 设计与实现

- 涉及模块：
  - `MobileClient/remote-control-shared/src/commonMain/kotlin/com/attach/mobile/logging/`
  - `MobileClient/androidApp/src/androidMain/kotlin/com/attach/mobile/android/logging/` 与 `MainActivity.kt`
  - `MobileClient/composeUI/src/iosMain/kotlin/com/attach/mobile/ui/AttachIosLogBridge.kt`
  - `MobileClient/iosApp/iosApp/iOSApp.swift`
  - `MobileClient/harmonyApp/entry/src/main/cpp/napi_init.cpp`
  - `MobileClient/composeUI/src/ohosMain/kotlin/com/attach/mobile/ui/logging/OhosLogBridge.kt`
- 核心流程：
  1. `remote-control-shared` 提供 `AttachLog` 门面、`LogWriter` 接口和 `setLogWriter()`。
  2. Android App 直接实现 `LogWriter` 并注入。
  3. iOS App 实现 `composeUI` 导出的 `ComposeLogWriter` 协议，并通过 `ComposeLogBridge` 注入；`ComposeLogBridge` 内部再委托给 `AttachLog`。
  4. HarmonyOS App 在 C++ 层实现 `OH_LOG_Print` 回调；K/N 侧通过 `SetAttachLogCallback` 注册回调，`InitializeAttachLogging` 启用写入器。
  5. 业务代码统一通过 `AttachLog.x(tag, message)` 记录日志。
- 重要约束：
  - `remote-control-shared` 与 `composeUI` 不实现具体日志后端。
  - 门面默认未注入 writer 时静默丢弃，不抛异常、不输出到 stdout。
  - 避免使用 `println` / `System.out.print` / `console.log` 记录诊断信息。
  - 不使用 `inline` 日志方法，避免跨模块 JVM target 不一致问题。

## 验证方式

- 命令：
  ```bash
  cd MobileClient
  gradle :remote-control-shared:testDebugUnitTest
  gradle :androidApp:assembleDebug
  gradle :composeUI:publishDebugBinariesToHarmonyApp
  gradle :composeUI:linkDebugFrameworkIosSimulatorArm64
  cd iosApp
  xcodebuild -project iosApp.xcodeproj -scheme iosApp -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' build
  ```
- 结果：
  - `:remote-control-shared:testDebugUnitTest` 通过。
  - `:androidApp:assembleDebug` 成功。
  - `:composeUI:publishDebugBinariesToHarmonyApp` 成功。
  - `:composeUI:linkDebugFrameworkIosSimulatorArm64` 成功。
  - `xcodebuild` iOS App 构建成功。

## 后续注意事项

- 后续新增敏感字段（如 SSH 密码、私钥）时，严禁直接传入 `AttachLog`。
  - 如需要日志级别开关或文件落盘，可在各平台 `LogWriter` 实现中扩展，shared 门面无需改动。
  - HarmonyOS 当前通过 C++ 回调写入 hilog；如需在 ArkTS 层控制日志开关，可增加一个 NAPI 方法动态启用/禁用回调。
  - iOS Swift 侧不直接依赖 `remote-control-shared` 的类型；若后续需要更多 Swift 桥接接口，应在 `composeUI/src/iosMain` 中以同样的薄桥接方式暴露。
