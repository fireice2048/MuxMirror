# Mobile KMP + CPF-CMP 客户端脚手架

## 背景

用户要求开始开发 Attach Mobile 客户端，并补充架构约束：KMP + Compose 跨平台移动客户端、`remote-control-shared` 公共远程控制模块、`composeUI` 公共 UI 模块、`iosApp` / `androidApp` / `harmonyApp` 三个平台入口，平台 app 不写业务逻辑，优先调试 HarmonyOS 但保持三端可编译。

## 关键结论

- 采用方案 A：参考 CPF-KMP-CMP Beta，让 Android、iOS、HarmonyOS 三端使用同一套 `composeUI` Compose 代码。
- `remote-control-shared` 只保存公共模型和纯逻辑，首个行为是终端输入 `↵` 换行插入。
- `androidApp`、`iosApp`、`harmonyApp` 仅保留平台入口和桥接。
- HarmonyOS 通过 `:composeUI:publishDebugBinariesToHarmonyApp` 将 KMP/CMP shared library、头文件和资源发布到 DevEco 工程，再用 `devecocli build` 编译。

## 影响范围

- 新增 `MobileClient/settings.gradle.kts`、`MobileClient/build.gradle.kts`、`MobileClient/gradle.properties` 和 `MobileClient/gradle/libs.versions.toml`。
- 新增 `MobileClient/remote-control-shared`、`MobileClient/composeUI`、`MobileClient/androidApp`、`MobileClient/iosApp`、`MobileClient/harmonyApp`。
- 更新 `MobileClient/README.md` 和根 `README.md` 说明客户端模块结构。

## 验证方式

- `cd Mobile && gradle :remote-control-shared:testDebugUnitTest`
- `cd Mobile && gradle :composeUI:publishDebugBinariesToHarmonyApp`
- `cd MobileClient/harmonyApp && devecocli build`
- `cd Mobile && gradle :androidApp:assembleDebug`
- `cd Mobile && gradle :composeUI:linkDebugFrameworkIosSimulatorArm64`
