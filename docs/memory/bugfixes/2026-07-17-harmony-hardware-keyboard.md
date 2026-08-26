# BugFix 记忆：鸿蒙 App 不支持物理键盘输入

## 现象

- 触发条件：鸿蒙模拟器（或外接键盘的真机）中，在 App 的 SSH 终端页用电脑物理键盘输入。
- 用户影响：物理键盘按键完全无反应；同一模拟器内浏览器地址栏可正常输入。

## 根因

1. 当前使用的 compose-multiplatform 鸿蒙版（1.9.2-0.3.0）未把 ArkUI 按键事件桥接进 Compose 按键分发：libkn 仅导出无参 `androidx_compose_ui_arkui_ArkUIViewController_onKeyEvent(void*)`，无法携带键值内容。
2. `harmonyApp/entry/.../Index.ets` 在 Compose 组件与宿主 Column 的 `onKeyEvent` 中 `return true` 消费了按键，却只调用无参 `nativeOnKeyEvent()`，键值内容被直接丢弃。
3. 修复过程中进一步发现（hilog 实证）：ArkUI `KeyEvent` 的 `unicode` 恒为键帽上档符号（字母恒大写、数字 2 → `@`、空格为 0），`keyText` 是键名（`KEYCODE_E`），且该 API 版本无 `pressedKeys` 修饰键状态——两者都不能用来还原真实输入字符。
4. 2026-07-18 工具条改造复查发现：终端页的 `DisposableEffect(server.id)` 直接捕获了首次组合时的 `input` 和 `sendInput`，处理器长期读取旧输入缓冲；输入状态变化不会重启该 Effect，连续物理按键可能基于过期文本编辑。

## 修复方案

- 涉及模块：`composeUI`（commonMain/ohosMain/androidMain/iosMain）、`harmonyApp`（Index.ets、napi_init.cpp、Index.d.ts）。
- 关键改动：
  - 自建桥接链：ArkTS `onKeyEvent` 转发 `keyCode` + Down/Up → NAPI 导出 `attachHardwareKey` → ohosMain `@CName("AttachHardwareKey")` → commonMain `setHardwareKeyHandler` 注册的处理器。
  - KMM 侧按键值表（2000-2009 数字、2017-2042 字母、2050 空格、2043/2044/2056-2064/2065/2066 符号）映射字符，并自行跟踪 Shift(2047/2048) Down/Up 得到大小写与上档符号；Enter(2054) 发送、DEL(2055) 删除。
  - 导航键：↑/↓(2012/2013)、ESC(2070)、FORWARD_DEL(2071)、TAB(2049) 直写 xterm 转义序列到 SSH 通道；←/→/HOME/END(2014/2015/2081/2082) 在本地缓冲非空时移动本地光标、为空时才转发远端；PGUP/PGDN(2068/2069) 不转发（zsh 未绑定 `\e[5~/\e[6~` 会回显 `~`），改为本地滚动终端输出。
  - commonMain 另保留 `onPreviewKeyEvent`（Compose 原生按键路径），供 Android 等能原生接收硬件按键的平台复用同一套缓冲编辑逻辑。
  - Effect 内需要读取持续变化的输入、发送函数和 CTRL/ALT 锁定态时，使用 `rememberUpdatedState`；不要把这些状态直接捕获进只以 `server.id` 为键的长期 Effect。
- 键值必须查官方表（`devecocli docs` 的 keyCode 文档），不能按 Android 键值平移推算：曾误判 2069 为 `+`（实为 PAGE_DOWN，鸿蒙 PLUS=2066、AT=2065、MOVE_HOME=2081、MOVE_END=2082）。

## 验证方式

- 复现步骤：模拟器进入 SSH 终端页，物理键盘（或注入）按键。
- 验证命令：`hdc shell uinput -K -d <keyCode> -u <keyCode>` 注入按键（对照实验：浏览器地址栏可收到注入字符，证明注入通道有效）。
- 验证结果：小写 `ls`/`pwd` 输入并回车执行成功（输出 `/Users/xpeng`）；Shift+p 输入大写 `P`；DEL 正确删除；`↑` 后 zsh 回调出上一条命令；PGDN 不再误出 `+`；软键盘 IME 通道回归正常。
- 备注：行缓冲模型下不要把光标编辑/翻页键无脑转发远端——远端行缓冲为空时转义序列是空操作（←/→/HOME/END 曾因此"无效"），zsh 未绑定的 `\e[5~/\e[6~` 会回显 `~`（PGUP/PGDN 曾因此出垃圾字符）；2026-07-17 已改为本地缓冲优先编辑、翻页本地滚动。

## 预防措施

- 鸿蒙侧需要按键/输入法行为时，先用一次性 hilog 探针打印 `KeyEvent` 各字段实测值，不要假设 `unicode`/`keyText` 语义。
- 自动化验收键盘输入：`uinput -K` 可达应用；`uitest uiInput keyEvent` 与 `uitest uiInput inputText` 对自绘 UI/隐藏输入框不可靠。
- compose-multiplatform 鸿蒙版升级后复查其是否原生桥接按键事件，若已支持可拆除自建桥接。
- 该版本 `FocusManager.moveFocus`（Down/Next）在 AlertDialog 内无法移动焦点，焦点切换需用显式 `FocusRequester` 链（2026-07-17 对话框物理键盘支持时实测）。
