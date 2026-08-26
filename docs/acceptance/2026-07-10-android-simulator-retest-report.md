# Android 模拟器复测报告

## 结论

Android Debug APK 重新编译通过，但本机 Android 模拟器未成功启动为可用 ADB 设备，因此无法安装、启动或执行 App 功能自测。本轮不能声明 Android 客户端可用，也没有把模拟器黑屏截图当作 App 自测通过证据。

## 执行环境

- 工程目录：`/Users/xpeng/Working/gitee/Attach/MobileClient/androidApp`
- Gradle Wrapper：上级目录 `../gradlew`
- APK：`MobileClient/androidApp/build/outputs/apk/debug/androidApp-debug.apk`
- AVD：`AttachE2E36`，启动端口 `5570`
- ADB：`/Users/xpeng/Library/Android/sdk/platform-tools/adb`

## 构建结果

执行命令：

```sh
cd /Users/xpeng/Working/gitee/Attach/MobileClient/androidApp
../gradlew :androidApp:assembleDebug --console=plain
```

结果：通过。

```text
> Task :androidApp:assembleDebug UP-TO-DATE
BUILD SUCCESSFUL in 2s
77 actionable tasks: 77 up-to-date
```

完整日志：`assemble-debug.log`（一次性构建输出，未随仓库保留）

## 模拟器与自测结果

执行了以下操作：

```sh
$HOME/Library/Android/sdk/platform-tools/adb start-server
$HOME/Library/Android/sdk/emulator/emulator -avd AttachE2E36 -port 5570 -no-snapshot -no-boot-anim -no-audio
$HOME/Library/Android/sdk/platform-tools/adb devices -l
```

模拟器进程存在，但 ADB 持续显示 `offline`，`adb -s emulator-5570 get-state` 返回 `error: device offline`。因此 APK 未安装，未执行服务器配置、连接、会话列表、读屏、输入或 resize 自测。

```text
List of devices attached
emulator-5570          offline transport_id:6

error: device offline
adb: device offline
```

证据：

- ADB 设备状态：`adb-devices.log`（一次性命令输出，未随仓库保留）
- 模拟器进程状态：`emulator-processes.log`（一次性命令输出，未随仓库保留）
- [模拟器现场截图（黑屏，非 App 通过证据）](evidence/android/2026-07-10-retest/emulator-offline-host-screen.png)

## 阻断项

- 两个旧实例 `AttachTest36b`、`AttachTest36` 持续处于 `U` 状态。
- 新实例 `AttachE2E36` 已运行超过两分钟但未完成 ADB 上线；启动时提示宿主可用内存低于模拟器推荐值（约 2.4GB / 5GB）。

在清理卡死实例并释放宿主内存、使 `adb devices -l` 显示 `emulator-5570 device` 前，不能进行有效 Android 模拟器自测。

## 复测准入条件

```sh
$HOME/Library/Android/sdk/platform-tools/adb devices -l
```

必须出现状态为 `device` 的 Android 模拟器；随后安装本轮 APK 并重新采集 App 首页、服务器连接、会话列表、读屏和输入的日志及截图。
