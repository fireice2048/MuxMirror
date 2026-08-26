# BugFix：Terminal.app 标签页定位失败

## 现象

- 在 macOS Terminal.app 中执行 `attach track` 时，日志出现 AppleScript `-1700` 类型转换错误。
- 会话仍会注册，但 `terminal_id` 为空，无法绑定 Terminal.app 的画面读取、输入和标签页操作。

## 根因

- Terminal.app 的 tab 不支持通过 `index of selected tab` 直接获得可转换为文本的索引；该表达式返回对象引用并在转换字符串时失败。

## 修复方案

- 检测当前标签页时遍历 `front window` 的标签页，使用循环整数序号比较 `selected tab`，再组成 `window_id:tab_index:tty`。
- 测试脚本必须包含标签页遍历和 `contents of i`，防止再次使用不兼容的 `index` 属性。

## 影响范围与验证

- 仅影响 `PCServer/attach/src/macos_terminal.rs` 的 Terminal.app 当前标签页识别。
- 执行目标测试，并通过 `osascript` 实测返回形如 `3359:1:/dev/ttys027` 的终端标识。
