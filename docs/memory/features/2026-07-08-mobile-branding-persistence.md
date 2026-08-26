# Mobile Branding And Server Persistence

## 背景

用户要求将 ATTACH 绿色火焰图用于移动端品牌资源：桌面图标使用 `icon-50.png`，首页顶部使用 `banner-70.png` 替代文字标题；同时修正首页添加按钮和列表操作图标，并解决新增/复制列表项重启后丢失的问题。

## 关键结论

- 服务器列表原先只保存在 `AttachApp` 的 `remember` 状态中，进程重启后必然恢复默认示例数据。
- 共享层新增 `encodeServerConfigs`/`decodeServerConfigs`，使用可测试的行格式保存服务器配置，避免为当前小规模数据引入数据库。
- Compose UI 通过 `expect object ServerConfigStore` 接入平台存储：Android 使用 `SharedPreferences`，iOS 使用 `NSUserDefaults`，HarmonyOS 使用应用文件目录文本文件。
- 首页 banner 进入 Compose resources；桌面图标和 App 显示名分别按 HarmonyOS、Android、iOS 的资源机制配置。

## 影响范围

- 影响移动端首页 UI、服务器列表增删改复制流程、Android/iOS/HarmonyOS App 名称和图标资源。
- 不改变 SSH 连接协议或 PC 端终端能力。

## 验证方式

- `./gradlew :remote-control-shared:testDebugUnitTest --rerun-tasks` 通过，覆盖编码解码、空列表、坏行忽略。
- `./gradlew :composeUI:compileDebugKotlinAndroid :androidApp:assembleDebug` 通过，覆盖 Android App 图标/名称资源和 Compose UI common/android 代码路径。
- `./gradlew :composeUI:publishDebugBinariesToHarmonyApp` 通过，覆盖 HarmonyOS Compose 共享库和资源发布路径；构建中存在既有 C adapter 生成代码 warning。
- `./gradlew :remote-control-shared:compileKotlinIosX64 :composeUI:compileKotlinIosX64` 通过，覆盖 iOS x64 Kotlin/Compose 编译路径。
