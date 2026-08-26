# BugFix 记忆：终端转义序列跨读块截断与 CR 覆盖缺失导致界面残留乱码

## 现象

- 触发条件：鸿蒙模拟器连接 SSH 终端（如首页 "MacBook Air"），远端 zsh 登录后。
- 用户影响：首屏残留两类乱码：
  1. `[?2004h`（zsh bracketed-paste 序列 `\x1B[?2004h` 的 ESC 消失，其余字节原样显示）。
  2. 一行 `%` + 填充空格（zsh `PROMPT_EOL_MARK`：上一条输出无换行时打印 `%`+空格填满行宽，再用 `\r` 回车让提示符覆盖；真实终端不可见，追加式渲染器残留可见）。

## 根因

- `composeUI` 的 `stripAnsiEscapeWithBuffer`（`MobileClient/composeUI/src/commonMain/kotlin/com/attach/mobile/ui/App.kt`）处理顺序错误：先用 `ANSI_ESCAPE_REGEX` 剥除完整序列，再用 `OTHER_CONTROL_REGEX` 删除控制字符，最后才检查末尾不完整转义。
- `OTHER_CONTROL_REGEX` 的字符范围 `\x0E-\x1F` 包含 `\x1B`（ESC），不完整序列的 ESC 在第三步前就被删掉，导致"末尾缓存（pending）"逻辑成为死代码——`lastIndexOf('\u001B')` 永远为 -1。
- 转义序列被 SSH 读块边界截断时（如 `\x1B` 与 `[?2004h` 分两块到达），ESC 被误删，剩余字节当作普通文本显示。
- 同类问题：OSC 分支 `\][^\x07]*\x07?` 中 BEL 可选，未到终结符的半个 OSC 会被当作完整序列提前剥除，后续内容泄漏为可见文本。
- 渲染缓冲区为纯追加式（`output += clean`），且旧代码用 `LONE_CR_REGEX` 直接删除孤立 `\r`，完全没有 CR 覆盖语义，`%`+空格无法被提示符覆盖。

## 修复方案

- 涉及模块：`MobileClient/composeUI`（commonMain UI 层）。
- 关键改动：
  1. 新增 `INCOMPLETE_ESCAPE_TAIL_REGEX = \x1B(\[[0-9;?]*|\][^\x07]*|[()])?$`，在剥除完整序列之后、删除其他控制字符之前，把末尾不完整转义尾部作为 pending 缓存，与下一块数据拼接后再处理。
  2. `ANSI_ESCAPE_REGEX` 的 OSC 分支 BEL 改为必选（`\x07?` → `\x07`），未终结 OSC 交给 pending 缓存。
  3. 移除 `LONE_CR_REGEX`，`\r` 不再被吞掉；新增 `appendTerminalOutput` 实现 CR 覆盖语义：行内 `\r` 丢弃当前行内容；块尾 `\r` 延迟判定（避免把跨块 `\r\n` 误判为行内回车）；**连续 `\r`（如 zsh 的 `\r\r\n`）只合并不删除**——真实终端里连续回车没有擦除效果，若按覆盖处理会误删上一行内容（曾导致 "Last login" 行被吃掉）；读取循环由 `output += clean` 改为 `output = appendTerminalOutput(output, clean)`。
  4. 函数可见性改为 `internal`，新增 `commonTest` 单元测试（`StripAnsiEscapeTest`，12 个用例），并在 `composeUI/build.gradle.kts` 增加 `commonTest` 的 `kotlin-test` 依赖。

## 验证方式

- 字节取证：macOS 上 `printf 'printf "abc"\nexit\n' | script -q out zsh -i` + `od -c` 确认 zsh 实际下发 `%`+空格+`\r` 及 `\x1B[?2004h`。
- 验证命令：`cd MobileClient && ./gradlew :composeUI:testDebugUnitTest --tests "com.attach.mobile.ui.StripAnsiEscapeTest"`；端到端按仓库"鸿蒙 KMM 共享库重打包"流程发布安装后连接实测。
- 验证结果：12 个单测全部通过（含跨块截断、OSC 半包、CR 覆盖、块尾 `\r` 延迟判定、连续 `\r` 不删行）；模拟器实测连接后提示符干净，不再出现 `%` 行和 `[?2004h` 乱码（截图确认）。

## 预防措施

- 处理"剥除 + 流式缓存"时，先提取不完整尾部再做字符级过滤；过滤正则的范围要复查是否误伤协议字符（如 ESC）。
- 终结符不要用可选量词"顺手兼容"半包数据，半包应显式进入 pending 缓冲。
- 追加式终端渲染不要直接删除 `\r`：行内 `\r` 是覆盖语义，块尾 `\r` 需等待下一块判定是否为 CRLF，连续 `\r` 无擦除效果只能合并不能删内容。
- 验证 HAP 内 .so 是否为新构建时，不要比对哈希（hvigor ProcessLibs 会 strip 符号，体积和哈希必然变化）；应搜索新代码特有的符号名（未 strip 的发布库）或安装后功能实测。
- 终端输出过滤逻辑改动必须跑 `StripAnsiEscapeTest`。
