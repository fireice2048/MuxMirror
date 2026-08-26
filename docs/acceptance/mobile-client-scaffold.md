# Mobile 客户端脚手架人工验收

## 前置条件

- 已安装 Java、Gradle、Android SDK、Xcode、DevEco Studio 和 `devecocli`。
- HarmonyOS 调试前已在 DevEco Studio 完成签名配置。
- 使用 CPF-KMP-CMP 兼容的 Kotlin/Compose Maven 仓库。

## 验收场景

### 场景 1：共享逻辑测试

运行：

```sh
cd Mobile
gradle :remote-control-shared:testDebugUnitTest
```

通过标准：`TerminalInputTest` 通过，`insertNewline` 支持空输入、末尾插入、中间插入和选区替换。

### 场景 2：Android 客户端编译

运行：

```sh
cd Mobile
gradle :androidApp:assembleDebug
```

通过标准：生成 Android debug APK，入口 Activity 仅挂载共享 `AttachApp()`。

### 场景 3：iOS 共享 Framework 编译

运行：

```sh
cd Mobile
gradle :composeUI:linkDebugFrameworkIosSimulatorArm64
```

通过标准：生成 iOS simulator framework，SwiftUI 入口通过 `MainViewController()` 挂载共享 UI。

### 场景 4：HarmonyOS 共享产物发布

运行：

```sh
cd Mobile
gradle :composeUI:publishDebugBinariesToHarmonyApp
```

通过标准：`MobileClient/harmonyApp/entry/libs/arm64-v8a/libkn.so`、`MobileClient/harmonyApp/entry/libs/x86_64/libkn.so` 和对应 `libkn_api.h` 被复制到 HarmonyOS 工程。

### 场景 5：HarmonyOS 客户端编译

运行：

```sh
cd MobileClient/harmonyApp
devecocli build
```

通过标准：Hvigor debug build 成功；若失败仅因签名、SDK 或 CPF Beta 依赖环境缺失，应记录具体错误并按 DevEco 指引修复环境。
