# 反馈记忆：鸿蒙 KMP 构建与模拟器联调的坑

## 坑点描述（按严重程度）

1. **只跑 `hvigorw assembleHap` 改 Kotlin 代码不生效**
   - 鸿蒙端是 KMP 架构，业务代码在 `composeUI` 的 Kotlin/Native 里，编成 `libkn.so` 后由 hvigor 打进 HAP。
   - `assembleHap` 只重编 ArkTS 壳和 `compose.har`，**不会重新编译 Kotlin**，所以改 `App.kt` 后界面仍是旧版。
   - 正确完整链路：`./gradlew :composeUI:publishReleaseBinariesToHarmonyApp`（重链 libkn.so 并拷到 `entry/libs/`）→ `hvigorw clean` → `hvigorw assembleHap` → `hdc install` → 强制重启 App。已封装为 `scripts/deploy-harmony-sim.sh`。

2. **`DEVECO_SDK_HOME` 被环境污染导致 hvigor 报 Configuration Error**
   - 现象：`hvigorw assembleHap` 报 `Invalid value of 'DEVECO_SDK_HOME'` 或 `SDK component missing`。
   - 根因：会话环境中 `DEVECO_SDK_HOME` 被设成无效值（空串或错误路径），hvigor 优先读该变量而非 `local.properties` 的 `hwsdk.dir`。
   - 正确值：`/Applications/DevEco-Studio.app/Contents/sdk/default/default`（与 `build-profile.json5` 的 `hwsdk.dir` 一致）。
   - 脚本里已 `export DEVECO_SDK_HOME=".../sdk/default/default"` 固定，避免环境干扰。

3. **`hdc uinput` 点击无法可靠命中 Compose 内容**
   - Compose（ArkUI）渲染的内容未暴露到系统 UI 树（`uitest dumpLayout` 只能看到状态栏等原生节点），`uinput -T -c x y` 坐标点击服务器列表项不生效，无法自动验证两级导航的视觉流程。
   - 正确做法：导航/视觉验证依赖人工在模拟器查看截图；自动验证改用编译通过 + 单元测试覆盖协议解析。

## 触发条件

- 在 macOS 上用 DevEco Studio + hvigor 构建/部署鸿蒙 App，且环境里 `DEVECO_SDK_HOME` 曾被错误设置过。
- 改动 `composeUI` 下 Kotlin 代码后用 `assembleHap` 单步构建。

## 正确做法（汇总）

- 改 Kotlin 业务代码后，必须走 `scripts/deploy-harmony-sim.sh` 完整链路，不要只跑 `assembleHap`。
- 脚本固定 `DEVECO_SDK_HOME` 指向 `sdk/default/default`，不要依赖外部环境变量。
- 模拟器视觉验证用截图 + 人工确认；Compose 内容自动点击验证不可行。

## 验证方式

- 命令：`sh scripts/deploy-harmony-sim.sh`
- 结果：HAP 重新生成并安装到模拟器（127.0.0.1:5555），App 重启生效。
