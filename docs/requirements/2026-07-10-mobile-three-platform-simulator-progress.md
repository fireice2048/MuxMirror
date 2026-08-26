# 三端模拟器自测进度

## 背景

需要在当前已配置好的 iOS、Android、鸿蒙三套开发环境中，分别编译移动端客户端并安装到模拟器运行，完成基础功能自测。若任一平台遇到构建、安装、启动或运行问题，由负责该平台的 Agent 在对应平台范围内排查并做最小修复。

## 目标

- iOS 客户端：编译、安装到 iOS 模拟器、启动运行，并收集日志或截图证据。
- Android 客户端：编译、安装到 Android 模拟器、启动运行，并收集日志或截图证据。
- 鸿蒙客户端：使用 `devecocli` 编译、安装到鸿蒙模拟器、启动运行，并收集日志或截图证据。
- 输出一份包含命令、结果、证据和问题处理记录的测试报告。
- 继续推进真实 PCServer 端到端验收，目标是连接、会话列表、读屏、输入和 resize 能被三端证明可用。

## 非目标

- 不新增产品功能。
- 不调整三端 UI 或交互，除非自测暴露出阻断运行的问题。
- 不修改与本次三端构建运行无关的 PCServer 能力。

## 执行计划

- [x] 启动 iOS Agent：负责 `MobileClient/iosApp` 与必要的 KMP iOS 产物构建，运行到 iOS 模拟器并留存证据。
- [x] 启动 Android Agent：负责 `MobileClient/androidApp` 与共享模块构建，运行到 Android 模拟器并留存证据。
- [x] 启动鸿蒙 Agent：负责 `MobileClient/harmonyApp`，必须通过 `devecocli` 构建、运行、采集日志并留存证据。
- [x] 汇总三个 Agent 的构建、运行、自测结果。
- [x] 如有平台修复，检查 diff 并运行对应验证命令。
- [x] 写入 `docs/acceptance/2026-07-10-mobile-three-platform-simulator-report.md` 测试报告。
- [x] 补充 iOS 真实 PCServer E2E 验收。
- [ ] 补充 Android 真实 PCServer E2E 验收；当前被 ADB/emulator 环境阻塞。
- [ ] 补充 HarmonyOS 输入发送验收；当前连接、列表、读屏通过，输入自动化未触发发送。
- [ ] 补充三端 resize 验收证据。

## 证据要求

每个平台至少提供以下一种现场证据：

- 构建/安装/启动命令的关键日志行。
- 模拟器现场截图文件路径。
- 运行日志中能证明 App 已启动或关键界面/能力已执行的日志行。

## 进度记录

- 2026-07-10：创建执行计划，准备启动三个平台 Agent 并行自测。
- 2026-07-10：iOS、Android、鸿蒙三端模拟器自测完成；Android 和鸿蒙各修复一处阻断问题；测试报告已写入 `docs/acceptance/2026-07-10-mobile-three-platform-simulator-report.md`。
- 2026-07-10：继续真实 PCServer E2E；iOS 连接、读屏、输入通过；Android 因 ADB 无可用设备且 emulator 进程卡死暂阻塞；HarmonyOS 补网络权限后连接、列表、读屏通过，输入发送未通过。
- 2026-07-10：Android 复测重新执行 `:androidApp:assembleDebug`，构建通过；新启动 `AttachE2E36`（`emulator-5570`）持续为 ADB `offline` 且黑屏，未能安装 APK 或执行 App 自测。详情见 `docs/acceptance/2026-07-10-android-simulator-retest-report.md`。
