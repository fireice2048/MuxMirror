# BugFix 记忆：Android 终端 ANSI 颜色未透传

## 现象

- 触发条件：Android 终端收到 Rust 核心的带 ANSI 样式输出。
- 用户影响：Android 终端文字全部使用默认绿字，无法表现与鸿蒙版相同的前景色、背景色和反色。

## 根因

- Rust 核心只在备用屏序列化 `styles` 样式区间，主屏的 `rebuild_view()` 会丢弃已解析的 ANSI 状态。
- Android `TmEvent` 和 Compose 渲染器已经定义了样式字段，但 `TermirrorCore.parseEvent()` 原先始终构造 `emptyList()`，导致样式在 JNA JSON 桥处丢失。
- Codex TUI 大量使用 SGR `1/22` 表达 `Ran`、`Working` 等高亮文字；核心原先忽略粗体状态，导致色值存在但字重和亮度层次不完整。

## 修复方案

- 涉及模块：`MobileApp/shared/src/terminal/mod.rs`、`MobileApp/androidApp/app/src/main/java/com/termirror/mobile/android/core/TermirrorCore.kt`、Android instrumentation 测试、Android 需求与 README。
- 关键改动：主屏改用带样式字符缓冲，复用 SGR 状态处理并按 UTF-16 生成样式区间；Android 使用内置 `JsonReader` 流式解析 `styles` 中的起止偏移、样式类型、前景色和背景色。
- 后续补充：主屏与备用屏同时保留 SGR `1/22` 跨读块状态，输出 `bold` 样式区间，Android Compose 使用 `FontWeight.Bold` 渲染。

## 验证方式

- 复现步骤：构造带 `styles` 数组的 `output` 事件并通过 Android 事件解析器处理。
- 验证命令：`cargo test --manifest-path MobileApp/shared/Cargo.toml`；`cd MobileApp/androidApp && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest`。
- 验证结果：Rust 73 个测试通过；Android 主工程和 instrumentation APK 编译成功；arm64-v8a 模拟器覆盖安装后，普通主屏文本、tmux 内容和状态栏的多色/背景色均已现场确认。

## 预防措施

- Android 事件解析测试覆盖带前景色、背景色、反色和无样式事件。
- Rust 主屏测试覆盖 ANSI 复位、跨读块状态、回车覆盖及非 BMP 字符的 UTF-16 偏移。
- Rust 测试覆盖主屏粗体复位与备用屏粗体跨读块保留；Android arm64 模拟器的 `tab-3` 现场确认 `Ran`、`Working` 已恢复粗体高亮。
- 新增事件字段时必须同步检查 Rust 序列化、各平台 FFI 桥和原生 UI 数据模型，不能只检查渲染组件是否已有字段。
