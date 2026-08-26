# BugFix 记忆：彩色背景上宽字符（CJK）格顶/底露黑缝（Span 背景盒按回退字体度量收缩）

## 现象

- 触发条件：鸿蒙终端渲染带背景色的宽字符，如 tmux 状态栏 `status-right` 的 `12-8月-26`（绿底）、任何 `ESC[42m`/`ESC[7m` 背景色行内的 CJK 字符。
- 用户影响：宽字符下方（实际是格的顶部和底部）出现黑色细缝，看起来像"下划线"或背景色块断裂；同一行内 ASCII 区段背景完好，只有 CJK 格露缝。

## 根因

- `TerminalNativeView.ets` 用 `Span.textBackgroundStyle` 画背景。含宽字符的段被拆成单字符 Span（为 letterSpacing 补偿宽度），CJK 字形走系统回退字体，其字体度量（ascent/descent）与 monospace 拉丁字体不同，导致该 Span 的背景盒垂直方向收缩。
- 像素级测量（Python+PIL 逐列扫描绿带）：普通格背景 y=458..515，CJK 格 y=464..513 —— 顶部缺 6px、底部缺 2px，缺的部分露出终端黑底。
- 尝试给 Span 加 `.lineHeight()` 无效：背景盒按 run 的字体度量计算，不随行高。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`（全仓唯一使用 textBackgroundStyle 的终端渲染组件，MUX 页同受益）。
- 关键改动：背景绘制从 Span 移到独立"背景色块层"——`bgLayer()` 单趟扫描 output+styles，把 offset 映射为 (行,列)（宽字符/代理对占 2 列），同行同色合并成色块；Scroll 内用 Stack 把色块层（`Row().position().width().height(LINE_HEIGHT).backgroundColor()`）垫在 Text 下面。内容 Span 只设 `fontColor`（`segmentColors` 简化为 `segmentFg`），光标 Span 保留自带 textBackgroundStyle。
- 反色规则镜像原逻辑：inverse 范围背景=前景色（无显式色用 TERMINAL_FG），显式背景色直接用。

## 验证方式

- 复现步骤：模拟器连本机 SSH → `tmux attach -t reg2` → `printf "\033[42mAB月CD\033[0m\n"`；或看 tmux 状态栏 `8月-26`。
- 验证命令：截图 `snapshot_display` + Python 逐列扫描色带纵向范围，确认 CJK 格与 ASCII 格背景完全连续（修复后整行统一 459..514）。
- 验证结果：受控 printf、tmux 状态栏、tab-13 全屏 TUI（Kimi CLI：圆角边框、Todo 盒、emoji、CJK）均与 `tmux capture-pane -t tab-13 -p | cut -c1-43` 地面真值逐行一致，黑缝消失。

## 预防措施

- **终端背景色不要用 `Span.textBackgroundStyle`**：只要内容可能含回退字体字形（CJK/emoji），背景盒就会按该字体的度量收缩。需要逐格精确背景的终端场景，一律用独立色块层（行高×列宽对齐）。
- 验证背景类渲染问题要看像素：JPEG 截图目视容易把 1~2px 的缝当成压缩噪点，用 PIL 逐列扫描色带纵向范围可以定量确认。
- `uitest uiInput inputText` 无法输入 CJK/引号（整串静默丢失，仅回车生效）；向 App 内 shell 注入测试命令改用宿主侧 `tmux send-keys -t <pane> <cmd> Enter`，可携带任意 UTF-8 与转义序列。
- ArkTS `build()` 内不允许局部变量声明（报 noNonUISyntax "Only UI component syntax can be written here"），计算结果只能内联调用方法或用 @State/@Computed。
