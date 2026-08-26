# BugFix 记忆：鸿蒙终端软键盘输入的三重坑（键盘类型 / text 绑定失效 / 发送收键盘）

## 现象

- 终端页软键盘输入命令时：首字母被自动大写（`Echo`）、空格键无响应（命令输不全）、按"发送"后软键盘自动收起、工具条符号键与软键盘输入互相冲掉内容。

## 根因

1. **小艺输入法的自动大写**：`InputType.Normal`/`USER_NAME` 键盘在字段为空时自动挂 shift，`TextInput.autoCapitalizationMode(NONE)`（API 20+）对其无效。
2. **InputType 副作用**：`Email` 不大写但吞空格；`Password` 触发系统隐私保护导致**整个窗口截屏全黑**（也不可取）。
3. **ArkUI TextInput 的 text 绑定不可靠**：输入框聚焦时组件文本由 IME 独占维护，`text`（含 `$$`）程序化写入不同步；随后 IME 的 `onChange` 会以组件内旧文本回写，把应用层缓冲冲掉（工具条插入的 `:` 被后续 IME 输入覆盖就是这么丢的）。
4. **`enterKeyType(Send)` 的 onSubmit 会让 IME 收起键盘**，终端需要连续输入。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/pages/TerminalPage.ets`
- 键盘类型选 `InputType.USER_NAME`（不大写副作用最少，空格可用、截屏正常），并在 `onInputChange` 里用 `normalizeImeCapital` 抑制：仅当 IME 在**空字段**处输入单个大写 ASCII 字母时转小写（字段非空时用户手动 shift 的大写不受影响）。
- 隐藏输入框**不绑 text**，只作"按键来源"：`prevFieldValue` 记录组件上次文本，`onChange` 用公共前缀 diff 出删除数与插入串，增量应用到本地缓冲（`insertAtCaret`/`removeBeforeCaret`）；缓冲状态（`inputText`/`caret`）完全由应用侧维护。
- `sendInput()` 末尾 `focusControl.requestFocus('tmHiddenInput')` 夺回焦点，保持键盘不收起。

## 验证方式

- 复现步骤：终端页唤起软键盘 → 输 `echo`（看首字母）、输带空格命令（`ls /usr/bin`）、发送后观察键盘、工具条符号键与软键盘混输。
- 验证结果：2026-07-21 Pura 90 Pro New 模拟器全部通过（缓冲显示 `ls /usr/bin`，服务端日志确认收到正确字节）。

## 预防措施

- ArkUI 输入组件与 IME 的交互必须以真机/模拟器实测为准，文档 API 行为（如 autoCapitalizationMode）不可尽信。
- 涉及隐藏输入框+IME 的场景，一律按"组件文本 IME 独占、应用只消费增量"设计，不要试图双向同步。
- 密码类 InputType 会黑掉截屏，验收截图场景禁用。

## 追加（2026-07-21 人工验收后二轮修复）

1. **光标键"无效"**：`caret` 是普通 private 字段，光标块按 caret 拆 Span 渲染，非 @State 不触发刷新。←→/HOME/END 实际改了 caret 但画面不动，被判"无效"。改 @State 后立即可见。
2. **DEL 误发远端**：原实现光标在缓冲末尾时落到 `writeRemoteAction`，把整行缓冲 + `\x1b[3~` 发到远端，用户看到"最左边添加乱码"。改为：缓冲非空且光标在末尾时不动作（右边没有内容）。
3. **⏏ 要按两次**：用户经 IME 自带按钮收键盘后 `keyboardRequestedVisible` 残留 true，⏏ 第一次点击误判"已显示"而走收起分支（无动作）。修复：`keyboardHeightChange` 高度为 0 时同步清掉该标记。
4. **软键盘退格**：正常路径（组件有文本）经 onChange 增量删除本地缓冲；空缓冲时补一条 `onKeyPreIme` 分支把 `\x7f` 发远端（覆盖 ↑ 翻历史后的行编辑；部分 IME 软键盘退格不投递按键事件，该路径仅对投递的生效）。
