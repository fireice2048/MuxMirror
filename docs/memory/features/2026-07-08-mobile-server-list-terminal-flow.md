# Mobile Server List Terminal Flow

## 背景

移动端客户端需要改成服务器列表优先流程：App 入口只负责平台承载，业务状态和 UI 分别放在 `remote-control-shared` 与 `composeUI`，三端共用 Compose UI。

## 关键结论

- `remote-control-shared` 新增 `ServerConfig` 和纯函数列表操作，覆盖新增、更新、复制、删除。
- `composeUI` 首页改为服务器列表，点击服务器进入模拟终端页。
- 终端页保留快捷键栏、输入框和独立 `↵` 换行按钮，并对输入区域应用 IME padding。
- CPF/KMP 当前环境中 `kmpPartiallyResolvedDependenciesChecker` 会长时间卡住，项目通过 `kotlin.kmp.unresolvedDependenciesDiagnostic=false` 和 `kotlin.kmp.eagerUnresolvedDependenciesDiagnostic=false` 关闭该诊断。
- 鸿蒙真机 HAP 构建可以通过，但安装需要本机 DevEco 自动签名写入匹配 `com.attach.mobile.harmony` 的 `signingConfigs`；签名密钥不提交。

## 影响范围

- `MobileClient/remote-control-shared`
- `MobileClient/composeUI`
- `MobileClient/gradle.properties`
- `MobileClient/harmonyApp` 的本地 arm64 产物

## 验证方式

- `cd Mobile && ./gradlew --no-configuration-cache --no-daemon --console=plain :remote-control-shared:testDebugUnitTest`
- `cd Mobile && ./gradlew --no-configuration-cache --no-daemon --console=plain :androidApp:assembleDebug`
- `cd Mobile && ./gradlew --no-configuration-cache --no-daemon --console=plain :composeUI:linkDebugFrameworkIosSimulatorArm64`
- `cd Mobile && ./gradlew --no-configuration-cache --no-daemon --console=plain :composeUI:linkDebugSharedOhosArm64`
- `cd MobileClient/harmonyApp && devecocli run --device 3XQ0224A11020136 --uninstall` 当前阻塞在调试签名缺失。
