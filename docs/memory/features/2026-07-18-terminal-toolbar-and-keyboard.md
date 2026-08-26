# 功能记忆：SSH 终端双行工具条与键盘联动

## 背景

- 需求来源：移动端 SSH 终端需要用两行等分工具条替代整屏复制、发送按钮和旧单行快捷键。
- 使用场景：手机软键盘输入 shell 命令时，快速输入符号、控制键、导航键并操作剪贴板。

## 关键功能点

- 两行各 10 个等宽、等高按钮，顺序固定并随屏幕宽度平均分配。
- 终端文本使用 Compose `SelectionContainer` 提供系统长按选择复制。
- CTRL/ALT 是持续锁定态：带下划线、激活高亮，再次点击解除。
- PAST 插入剪贴板文本；⏏ 切换键盘，并根据 IME inset 翻转方向。
- 工具条位于终端下方，通过系统 `KeyboardAvoidMode.RESIZE` 与 Compose IME inset 跟随键盘。

## 设计与实现

- 涉及模块：`MobileClient/composeUI`、`MobileClient/harmonyApp`（沿用既有 RESIZE 配置）。
- 核心流程：隐藏 `BasicTextField` 接收软键盘编辑；普通文字进入本地输入缓冲，CTRL/ALT 锁定时转为控制字符或 ESC 前缀直接写 SSH；方向与功能键使用 xterm CSI 序列。
- 重要约束：KMM 共享 UI 变更后必须重新发布 `libkn.so`，清理鸿蒙工程再打包；否则 HAP 可能继续携带旧 UI。
- 键盘动画以 ArkUI `KeyboardAvoidMode.RESIZE` 为主。当前 OHOS Compose 的 `WindowInsets.ime` 源码注明不提供自身动画，不应再叠加一套手动位移动画。

## 验证方式

- 命令：`./gradlew :composeUI:compileKotlinOhosX64 :composeUI:testDebugUnitTest`
- 结果：OHOS x64 编译与 Android common 单测通过；xterm 修饰序列、CTRL/ALT 字符转换和输入编辑检测均有单测覆盖。
- 人工验收：见 `docs/acceptance/2026-07-18-terminal-toolbar-redesign.md`。

## 后续注意事项

- 修改工具条或键盘联动后，至少验证键盘连续弹出/收起 5 次，并截图确认工具条与键盘上沿贴合。
- `PAST` 是产品指定标签，虽然英文常用写法是 `PASTE`，不要自行更名。
