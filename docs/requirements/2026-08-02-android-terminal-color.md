# Android 终端 ANSI 颜色同步需求

日期：2026-08-02
状态：开发中（现场回归补充主屏颜色）

## 背景

Rust 终端核心已经解析远端 SSH 输出中的 ANSI 前景色、背景色、256 色、RGB 色、弱化和反色，并通过 `output` 事件携带 `styles` 区间。鸿蒙版 App 已消费这些区间；Android 端虽然定义了相同的数据模型和 Compose 渲染能力，但事件 JSON 解析暂未透传 `styles`，终端文字因此全部使用默认绿色。

## 目标

- Android 终端消费 Rust `output` 事件中的 `styles` 字段。
- Android 端按 Rust 提供的 UTF-16 区间渲染前景色、背景色、粗体、弱化和反色。
- 无样式事件继续使用现有默认黑底绿字行为。
- Android 颜色表现与当前鸿蒙版渲染结果保持一致。
- 普通 shell 主屏与 tmux/rmux 备用屏都必须保留远端 ANSI 样式，不能只给状态栏或全屏 TUI 上色。

## 平台需求

- Android 原生 Compose UI。
- 不改变 SSH 协议、Rust 终端快照协议和 HarmonyOS NAPI 接口。
- 不引入新的服务端依赖或配置格式。

## 关键流程

1. Rust 终端核心解析 ANSI 并通过 C ABI 发送 `styles`。
2. Android JNA 事件桥解析样式区间及可选前景色、背景色。
3. Android `TerminalComposeView` 将样式区间转换为 `AnnotatedString` 的 `SpanStyle`。
4. 通过构建、单元测试和真机/模拟器终端验收确认颜色、光标和输入行为未回归。

## 当前进度

- [x] Android JNA 事件桥解析 `styles` 样式区间。
- [x] Android Compose 继续复用已有 `AnnotatedString` 颜色渲染。
- [x] Rust 核心测试通过。
- [x] Android 主工程与 instrumentation 测试编译通过。
- [x] Android 模拟器完成首次安装运行，确认备用屏背景色/反色已生效。
- [x] Rust 主屏缓冲保留 ANSI 前景色、背景色、弱化和反色样式。
- [x] 重建 Rust Android 动态库与 APK，在模拟器对比普通 shell 和 tmux/rmux 颜色。
- [x] 保留 ANSI SGR `1/22` 粗体状态，修复 Codex 等 TUI 的高亮文字层次。

## 非目标

- 本轮不实现完整终端主题配置或服务端终端调色板同步。
- 本轮不修改鸿蒙版 UI。

## 待澄清问题

- ANSI 16 色仍使用 Rust 核心统一调色板；服务端终端若使用自定义主题，其索引色与 App 可能存在色值差异，后续可增加主题配置。
