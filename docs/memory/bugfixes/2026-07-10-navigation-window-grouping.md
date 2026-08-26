# BugFix 记忆：移动端导航页按 session 而非按窗口分组

## 现象

- 触发条件：在 macOS Terminal.app 的多个窗口/标签页执行 `attach track` 后，打开移动端导航页。
- 用户影响：导航页每个被 track 的标签页显示为独立的一行（N 个标签页 = N 行），且每行 title 全部为 `Apple_Terminal`（来自 `TERM_PROGRAM` 环境变量）。不符合"一个窗口一行、行内按钮对应各标签页"的需求。

## 根因

两个独立缺陷叠加：

1. **客户端发错协议**：`MobileClient/remote-control-shared/.../TcpTerminalClient.kt` 的 `listWindows()` 实际发送的是 `list_sessions`，并把每个 `TerminalSession` 直接映射成一个"窗口"（单行 + 一个标签）。这是 6 行 + `Apple_Terminal` 标题的直接来源。
2. **服务端 AppleScript 非法属性**：`PCServer/attach/src/macos_terminal.rs` 的 `TerminalAppAdapter::list_all_tabs` 用 `name of tab` 取标题，而 Terminal.app 的 `tab` 没有 `name` 属性（错误 -1728），导致 `list_windows` 直接报错。
3. **潜在拼接缺陷**：AppleScript `return results as string` 会把列表项**无分隔符拼接**成一行，即使上面修好也会被合并成单行。

## 修复方案

- 涉及模块：`MobileClient/remote-control-shared`、`PCServer/attach`
- 关键改动：
  - `TcpTerminalClient.listWindows` 改为先 `list_sessions` 找到一个带 macOS 终端绑定的 tracked session，再发 `list_windows` 并按 `window_id` 解析窗口分组；失败时回退到原有 session 列表，保证降级可用。
  - 新增 `parseWindowList` / `findTrackedTerminalSessionId` 解析器与单元用例。
  - `list_all_tabs` 的 AppleScript 改用 `custom title of t`（若 `title displays custom title of t` 且非空，否则 `name of w`）取标签标题，并用 `text item delimiters` 以换行分隔结果。
  - 内部 `TabInfo` 增加 `window_title` 字段，`list_windows` 用它作为窗口行标题，并新增 `clean_terminal_window_title` 去掉 Terminal.app 标题末尾的 ` — WxH` 尺寸后缀。

## 验证方式

- 复现步骤：Terminal.app 开多窗口多标签页 → 各标签执行 `attach track` → 移动端进入导航页。
- 验证命令：`attach list-windows <tracked-session-id>`（需 TERM_PROGRAM=Apple_Terminal 的服务进程）。
- 验证结果：返回按 `window_id` 正确分组的窗口数组，每个窗口含其全部标签页，窗口标题已去除尺寸后缀；Rust 单测 74 项全过，Kotlin shared 模块编译通过。

## 预防措施

- macOS AppleScript 取标签/窗口标题不要直接用 `name of tab`；Terminal.app 用 `custom title of tab` + `title displays custom title of tab` 判断。
- AppleScript 返回多行结果务必用 `text item delimiters` 显式加换行，避免 `as string` 无分隔符拼接。
- `list_windows` 是"按窗口分组"的唯一正确协议，客户端导航页应始终走它，不要用 `list_sessions` 伪造窗口。
