# 功能记忆：鸿蒙/Android 终端默认前景色改为浅灰对齐 PC 端（iOS 本已对齐）

## 背景

- 需求来源：用户在 tab-2（kimi CLI TUI）会话现场对比，发现模拟器上的文字颜色与 Mac 本地终端不一致，要求自测并修正。
- 历史约束：2026-07-26 ANSI 颜色功能曾明确要求"默认主题仍为绿字深色背景"（品牌浅绿 `#B7F7C1`）。本次用户明确要求与 PC 端观感一致，推翻该约束。

## 现象与定位

- 现象：模拟器上 kimi TUI 的旁白正文、`> ` 提示符、光标块均为浅绿色，Mac 终端为浅灰/白色。
- 定位：`tmux capture-pane -e -p -t tab-2` 确认这些文本使用 `ESC[39m`（默认前景色），无显式 RGB；即差异来自 App 的默认前景色回退值。
- 根因：`TerminalNativeView.ets` 的 `segmentColors()` 对无显式颜色的段回退到 `TERMINAL_GREEN`（`#B7F7C1`），光标与容器 `fontColor` 同用该常量。

## 关键改动

- 文件：`MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`
- 默认前景色 `#B7F7C1` → `#E0E0E0`（常量改名 `TERMINAL_FG`）；弱化色 `#718078` → 中性灰 `#7F7F7F`。
- 覆盖式光标与隐藏态光标同步改用 `TERMINAL_FG`（透明底色 `#00B7F7C1` → `#00E0E0E0`），与 PC 端"反色默认前景"的观感一致。
- 显式 ANSI 颜色（RGB/256/标准色）、tmux 绿底黑字状态栏不受影响。

## 影响范围

- 仅鸿蒙端终端内容区默认文字/光标颜色；网络诊断页（`NetworkDiagPage.ets`）保留自己的绿色常量，未改动。
- 2026-08-02 同日补齐 Android：`TerminalComposeView.kt` 的 `TerminalGreen #B7F7C1` → `TerminalFg #E0E0E0`，弱化色 `#718078` → `#7F7F7F`，光标块同步改用 `TerminalFg`；`./gradlew :app:compileDebugKotlin` 编译通过。`Theme.kt` 的品牌绿（主题色）与 `NetworkDiagScreen.kt` 的诊断页绿未动。
- iOS 无需改动：`TerminalTextView.swift` 默认前景已是 `#E5E5E5`（对齐 macOS Terminal Clear Dark profile），光标同色。

## 验证方式

- `cd MobileApp/harmonyApp && devecocli build --build-mode debug` 增量构建成功。
- `devecocli run --device "Pura 90 Pro" --skip-build --build-mode debug` 覆盖安装启动。
- 模拟器进入"自测"连接，`tmux switch-client -t tab-2` 切到同一会话，截图与 `screencapture` 的 Mac 屏幕逐项对比：旁白正文、`> ` 提示符、光标块均为浅灰/白色，与 Mac 一致；蓝色标题、紫色 `$`、琥珀色 `yolo`、绿底状态栏保持正确。
- Android 上机自测：`./gradlew :app:installDebug` 装到 Medium_Phone 模拟器（emulator-5554），进 TestServer 连接并 `tmux switch-client -t tab-2`，`adb exec-out screencap` 截图逐项对比：旁白正文、`> ` 提示符、白色光标块、显式 ANSI 颜色与绿底状态栏均与 Mac 一致。
