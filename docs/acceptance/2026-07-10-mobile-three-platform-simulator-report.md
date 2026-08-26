# Mobile 三端模拟器自测报告

## 结论

2026-07-10 已完成 iOS、Android、HarmonyOS 三端客户端的模拟器构建、安装、启动与专项自测。基础启动能力三端均通过；真实 PCServer 端到端能力目前达到：

- iOS：PASS，已连接真实 PCServer，完成会话列表、读屏、发送输入。
- Android：基础运行 PASS；真实 PCServer E2E 受本机 Android emulator/ADB 环境阻塞，未完成 App 侧验证。
- HarmonyOS：PARTIAL，已连接真实 PCServer，完成会话列表和读屏；输入发送在当前模拟器自动化下未触发，未通过。

因此，本轮还不能声明“产品所有功能完全可用”。已把发现的产品阻断项修复到代码中，并把剩余未达标项记录为后续必须处理的验收缺口。

## 本轮修复

- Android：补 `android.permission.INTERNET` 并将 TCP 请求移出主线程，修复 `EPERM` / `NetworkOnMainThreadException`。
- HarmonyOS：修复日志回调声明冲突；补 `ohos.permission.INTERNET`，修复 `socket(AF_INET, SOCK_STREAM, 0)` 创建失败。
- iOS / native：修复 IPv4 地址字节序，iOS simulator 可连通宿主机 PCServer。
- 共享协议：移动端改为使用 PCServer `list_sessions` 和真实 session id，读屏/输入/resize 不再注册伪造 tracked session。
- 配置存储：服务器配置编码新增 token 字段，保留 6 字段旧配置兼容；新增 token 输入框。

## 复验命令

```sh
cd MobileClient
./gradlew :remote-control-shared:test --console=plain
```

结果：PASS，`BUILD SUCCESSFUL in 4s`。

```sh
cd MobileClient
./gradlew :androidApp:assembleDebug --console=plain
```

结果：PASS，`BUILD SUCCESSFUL in 815ms`。

```sh
cd MobileClient
./gradlew :composeUI:linkDebugFrameworkIosSimulatorArm64 --console=plain
```

结果：PASS，`BUILD SUCCESSFUL in 47s`。

```sh
cd MobileClient/harmonyApp
devecocli build
devecocli run --module entry --device 127.0.0.1:5555 --skip-build
```

结果：PASS，`Build completed successfully!`，`Application 'com.attach.mobile.harmony': start ability successfully.`。

## iOS 验收

环境：iPhone 16 Pro / iOS 18.5，UDID `E067BA29-6871-4670-A343-D3446EEFB13A`。

结果：

- KMP iOS simulator framework 编译通过。
- Xcode Debug simulator App 编译、安装、启动通过。
- 主界面、服务器配置、终端窗口入口可用。
- 真实 PCServer E2E 通过：连接 `127.0.0.1:48740`，列出 1 个 session，进入 `cat` 会话，读到 `mobile-e2e-ready`，发送 `ios-mobile-e2e-ok` 后服务端读屏可见。

证据：

- 主界面截图：[2026-07-10-ios-main-screen.png](evidence/ios/2026-07-10-ios-main-screen.png)
- E2E 截图：[04-after-ui-test-pass2.png](evidence/ios/04-after-ui-test-pass2.png)
- App 关键日志：[ios-app-key-log-pass2-redacted.txt](evidence/ios/ios-app-key-log-pass2-redacted.txt)
- 服务端读屏：[cli-read-screen-after-ios-pass2.txt](evidence/ios/cli-read-screen-after-ios-pass2.txt)
- 最终构建日志：`ios-final-link-after-fixes-2026-07-10.log`（一次性构建输出，未随仓库保留）

关键日志：

```text
[I/TcpTerminalClient] listing sessions from 127.0.0.1:48740
[D/TcpConnection] connected to 127.0.0.1:48740
[I/TcpTerminalClient] loaded 1 sessions
[I/TerminalScreen] entering tab cat of window cat
[I/TcpTerminalClient] sending 18 chars to window=pty-... tab=cat
[D/TcpTerminalClient] input accepted
[D/TcpTerminalClient] read 74 chars
```

## Android 验收

环境：基础自测使用 `AttachTest36b` / `emulator-5556`。后续 E2E 复测时本机 ADB 无可用设备。

结果：

- `:androidApp:assembleDebug` 编译通过。
- 初始模拟器安装、启动、主界面展示通过。
- 点击服务器后不再出现网络权限或主线程网络异常；在无服务环境下错误收敛为连接失败。
- 真实 PCServer E2E 未完成：复测时 `adb devices -l` 为空，旧 emulator 进程处于不可中断 `U` 状态，新启动 emulator 未注册为可用 ADB device。

证据：

- 基础运行截图：[android-final-server-open-2026-07-10.png](evidence/android/android-final-server-open-2026-07-10.png)
- 基础运行 logcat：[android-final-logcat-2026-07-10.txt](evidence/android/android-final-logcat-2026-07-10.txt)
- 最终构建日志：`android-final-assemble-after-fixes-2026-07-10.log`（一次性构建输出，未随仓库保留）
- ADB 设备状态：[android-final-adb-devices-2026-07-10.txt](evidence/android/android-final-adb-devices-2026-07-10.txt)
- emulator 进程状态：[android-final-emulator-processes-2026-07-10.txt](evidence/android/android-final-emulator-processes-2026-07-10.txt)

关键日志：

```text
07-10 01:02:09.379 I/ActivityTaskManager: Displayed com.attach.mobile/.android.MainActivity
07-10 01:02:11.394 I/TcpTerminalClient: listing windows from 127.0.0.1:22
07-10 01:02:11.398 E/TcpConnection: java.net.ConnectException: failed to connect ... ECONNREFUSED
```

最终 ADB 状态：

```text
List of devices attached
```

## HarmonyOS 验收

环境：Pura 90 Pro / HarmonyOS 7.0.0 Beta1，设备 `127.0.0.1:5555`。构建、运行、日志采集均使用 `devecocli`；配置文件注入与截图使用 `hdc` 的文件和截图能力。

结果：

- `devecocli build`、`devecocli run` 通过。
- 主界面和服务器列表展示通过。
- 通过 debug app 私有目录写入配置，App 启动后读取 `/data/storage/el2/base/haps/entry/files/attach_server_configs.txt` 成功。
- 补 `ohos.permission.INTERNET` 后，App 可连接 PCServer，列出 1 个 `cat` 会话。
- 进入会话后读屏通过，截图可见 `harmony-e2e-live-session`。
- 输入发送未通过：`uitest uiInput` 能弹出输入法，但文本没有可靠进入 Compose 输入框，日志未出现 `sending ...` / `input accepted`，服务端读屏未出现 `harmony-send-ok`。

证据：

- 真实配置主界面：[harmony-after-permission-server-2026-07-10.jpeg](evidence/harmony/harmony-after-permission-server-2026-07-10.jpeg)
- 会话列表截图：[harmony-live-session-list-2026-07-10.jpeg](evidence/harmony/harmony-live-session-list-2026-07-10.jpeg)
- 读屏截图：[harmony-read-screen-2026-07-10.jpeg](evidence/harmony/harmony-read-screen-2026-07-10.jpeg)
- 连接日志：[harmony-live-session-click-log-2026-07-10.txt](evidence/harmony/harmony-live-session-click-log-2026-07-10.txt)
- 读屏日志：[harmony-read-screen-log-2026-07-10.txt](evidence/harmony/harmony-read-screen-log-2026-07-10.txt)
- 输入未通过日志：[harmony-send-input-retry-log-2026-07-10.txt](evidence/harmony/harmony-send-input-retry-log-2026-07-10.txt)
- 输入后服务端读屏：[harmony-pcserver-after-send-retry-2026-07-10.txt](evidence/harmony/harmony-pcserver-after-send-retry-2026-07-10.txt)

关键日志：

```text
07-10 07:54:34.414 D ServerConfigStore: loaded 111 chars from /data/storage/el2/base/haps/entry/files/attach_server_configs.txt
07-10 07:54:34.414 I AttachApp: loaded 1 saved servers
07-10 07:55:12.075 I TcpTerminalClient: listing sessions from 10.184.126.32:48740
07-10 07:55:12.077 D TcpConnection: connected to 10.184.126.32:48740
07-10 07:55:12.387 I TcpTerminalClient: loaded 1 sessions
07-10 07:55:38.992 I TerminalScreen: entering tab cat of window cat
07-10 07:55:39.018 D TcpTerminalClient: read 52 chars
```

## 功能可用状态

| 功能 | iOS | Android | HarmonyOS | 备注 |
| --- | --- | --- | --- | --- |
| Debug 构建 | PASS | PASS | PASS | 主 Agent 最终复验 |
| 安装启动 | PASS | PASS | PASS | 三端均有日志或截图 |
| 服务器列表 | PASS | PASS | PASS | 三端均可展示 |
| 保存 token 配置 | PASS | BUILD PASS | PASS | Android E2E 未复验，代码路径共享 |
| 连接真实 PCServer | PASS | BLOCKED | PASS | Android 被 ADB/emulator 阻塞 |
| 列出会话 | PASS | BLOCKED | PASS | iOS/Harmony 有真实服务证据 |
| 终端读屏 | PASS | BLOCKED | PASS | iOS/Harmony 有截图或日志 |
| 发送输入 | PASS | BLOCKED | FAIL | Harmony 自动输入未触发发送 |
| resize | NOT TESTED | BLOCKED | NOT TESTED | UI 当前未提供显式 resize 操作证据 |
| 崩溃检查 | PASS | PASS | PASS | 未见 App crash；Harmony crash 日志为空 |

## 后续必须处理

- Android：清理卡死的 emulator/ADB 环境后，重新执行真实 PCServer E2E，覆盖连接、会话列表、读屏、输入。
- HarmonyOS：修复或增强终端输入交互，使文本输入和发送按钮在模拟器输入法/自动化下可靠触发 `sendInput`。
- resize：补充可操作入口或自动触发策略，并为三端增加 resize 验收证据。
