# 输入框键盘行为修正

## 背景

1. 服务器配置对话框的密码输入框未设置 `KeyboardOptions`，软键盘自动纠正/首字母大写会篡改密码内容，导致认证失败且难以察觉。
2. 鸿蒙模拟器中电脑的物理键盘输入在 App 内无效（模拟器自带浏览器正常）。排查结论：当前使用的 compose-multiplatform 鸿蒙版未把 ArkUI 按键事件桥接进 Compose 按键分发（libkn 仅导出无参 `onKeyEvent` 钩子，无法携带键值）；且 `harmonyApp` 的 `Index.ets` 在 `onKeyEvent` 中消费了按键却未转发键值内容，物理键盘输入被直接丢弃。

## 目标

1. 密码输入框（含用户名输入框）禁用自动纠正与首字母大写；密码框使用 `KeyboardType.Password`。
2. SSH 终端输入框同样禁用自动纠正/首字母大写，避免命令被输入法改写。
3. SSH 终端页支持物理键盘：可打印字符写入输入缓冲，Backspace 删除，Enter 发送当前行；Ctrl/Alt/Meta 组合键不拦截。

## 平台需求

- 主要验证平台：HarmonyOS 模拟器；Compose 改动位于 `composeUI` commonMain，桥接改动位于 ohosMain 与 `harmonyApp`。

## 关键流程

- `ServerDialog` 用户/密码 `OutlinedTextField` 增加 `KeyboardOptions`。
- 物理键盘桥接（鸿蒙专用）：
  - `Index.ets` 的 `onKeyEvent` 提取 `keyCode`/`unicode`（`KeyType.Down` 时），经 NAPI 导出 `attachHardwareKey` 传入 KMM。
  - ohosMain `HardwareKeys.ohos.kt` 以 `@CName("AttachHardwareKey")` 导出并回调 commonMain 注册的处理器；`napi_init.cpp` 增加同名 NAPI 包装。
  - `SshTerminalScreen` 通过 `DisposableEffect` 注册处理器：Enter(2054) → 发送，DEL(2055) → 删除光标前字符，其余可打印 unicode 插入光标处。
- commonMain 另保留 `onPreviewKeyEvent`（Compose 按键路径），供能原生接收硬件按键的平台（如 Android）使用；两条路径复用同一套缓冲编辑逻辑。
- 验证方式：模拟器内 `uinput -K -d <keyCode> -u <keyCode>` 注入按键（已用浏览器地址栏对照验证该注入可达应用输入框），截图核对终端缓冲、删除与发送。

## 非目标

- 不支持 Tab 补全、Ctrl+C 等控制键转发。
- 不改动软键盘 IME 输入路径。
- 不修改 compose-multiplatform 鸿蒙版本身的按键桥接缺陷（库外绕过）。

## 待澄清问题

- 无。

## 2026-07-17 补充：对话框文本框物理键盘支持

- 现象：终端页物理键盘可用后，服务器编辑对话框（`ServerDialog`）内物理键盘仍无反应。根因：对话框使用 Compose `OutlinedTextField`，其文本来自系统 IME 提交；鸿蒙版 compose-multiplatform 不桥接按键事件，且 KMM 侧处理器只在终端页注册。
- 方案：`ServerDialog` 五个字段改为 `TextFieldValue` 状态，新增 `Modifier.hardwareKeyTextInput`（commonMain `App.kt`）：持有焦点期间注册键值处理器（复用键值表/Shift 跟踪/光标编辑），失焦或离开组合时注销；`hardwareKeyTextFieldOwner` 令牌防止焦点切换时失焦方误注销他方处理器。
- 行为：可打印字符插入光标处，DEL 删除光标前字符，←/→ 移动光标，ENTER/TAB 移动焦点到下一字段。
- 实现注意：compose-multiplatform 鸿蒙版的 `FocusManager.moveFocus`（Down/Next 均实测）无法在该对话框内移动焦点，改用显式 `FocusRequester` 链（`focusField(i+1).requestFocus()`）实现切换。
- 验证：模拟器打开编辑对话框，`uinput -K` 注入按键，截图核对字符进入焦点字段、删除与焦点切换（ENTER/TAB 均实测通过）。

## 2026-07-17 补充：终端导航键行为修正

- 现象：终端页物理键盘 ←/→/HOME/END 无效，PGUP/PGDN 在终端里回显垃圾 `~`。
- 根因：行缓冲模型下输入字符留在本地缓冲、回车才发远端，远端行缓冲为空；光标编辑键被转发为 xterm 转义序列后远端无可移动内容（空操作），而 zsh 未绑定 `\e[5~/\e[6~` 会把 `~` 回显出来。
- 修正（`handleTerminalHardwareKey`）：本地缓冲非空时 ←/→/HOME/END 直接移动本地缓冲光标；缓冲为空时才转发远端（供 ↑ 回调历史后编辑）；PGUP/PGDN 不再转发，改为本地滚动终端输出（按视口高度翻页）。
- 验证：`uinput -K` 注入，`ec▌ho`（←×2）、Home 后插入 `x` 得 `x▌echo`、End 后追加 ` ok`、PGUP/PGDN 翻页无 `~`、↑ 历史回调保持正常。
