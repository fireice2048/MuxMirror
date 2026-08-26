# Android/iOS 全屏 TUI 远端回看需求

## 背景

鸿蒙端已经通过终端鼠标协议实现 Codex、OpenCode、Claude Code、Kimi Code 等全屏 TUI 的远端内容回看。Android 与 iOS 当前只有客户端本地文本滚动，无法操作全屏 TUI 自己维护的历史，需要补齐一致的交互和协议能力。

## 目标

1. Android 与 iOS 均支持双指纵向滑动，向启用鼠标跟踪的远端全屏 TUI 发送滚轮事件。
2. 保留单指本地滚动，用于普通 Shell 输出和客户端已有历史。
3. 工具栏及外接键盘的 `PGUP` / `PGDN` 根据鼠标跟踪状态切换：全屏 TUI 中按页发送远端滚轮，普通 Shell 中执行本地翻页。
4. 复用 Rust 核心上报的 `mouseProtocol`，不按 Codex 等具体应用名称做特判。
5. 鼠标跟踪关闭时不发送滚轮转义序列，避免污染普通 Shell 输入。

## 平台需求

- Android 使用 Jetpack Compose 手势输入，与现有 `verticalScroll` 协同工作。
- iOS 使用双指 `UIPanGestureRecognizer`，与 `UITextView` 的单指滚动并行识别。
- 两端均支持 Rust 核心提供的 SGR 和传统 X10 鼠标滚轮编码。
- 滚轮坐标取终端可视区域中心，并钳制到当前 PTY 行列范围内。

## 关键流程

1. Android/iOS 解析 Rust `output` 事件中的 `mouseProtocol`（`none`、`x10` 或 `sgr`）。
2. 双指纵向位移按固定阈值累计；达到阈值时发送对应方向的远端滚轮，每次手势更新限制事件数量。
3. 手指向下移动对应滚轮向上，手指向上移动对应滚轮向下，与终端内容拖动方向一致。
4. `PGUP` / `PGDN` 在鼠标模式下各发送 8 个滚轮事件；非鼠标模式下滚动一个本地可视页。
5. Android 与 iOS 的外接键盘 Page Up/Page Down 复用同一上下文逻辑。

## 非目标

- 不改变单指滑动为远端输入。
- 不实现远端鼠标点击、选择或拖拽。
- 不为 Codex、OpenCode、Claude Code、Kimi Code 分别维护应用名单。
- 不修改 SSH、tmux/rmux 或 PCServer 协议。

## 验收标准

1. 支持鼠标滚轮的全屏 TUI 中，Android/iOS 双指上下滑动可回看和返回应用内部历史。
2. 普通 Shell 中单指仍可本地回看，双指不会插入乱码。
3. 两种状态下工具栏和外接键盘 `PGUP` / `PGDN` 行为均符合目标。
4. 单元测试覆盖协议编码、坐标钳制和距离累计。
5. Android Debug APK 与 iOS 模拟器工程构建通过。

## 待澄清问题

- 不同 TUI 是否启用鼠标跟踪由应用和 tmux/rmux 配置决定；若电脑端鼠标滚轮也无法操作，客户端不能绕过远端配置限制。
