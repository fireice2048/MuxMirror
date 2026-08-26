# 需求：终端显示组件抽象与原生方案重构

## 背景

终端显示最初完全内联在 TerminalPage 中：Rust 侧 TerminalBuffer 解析 ANSI → 整屏纯文本快照
→ ArkTS Text/Span 渲染。代码耦合严重，无法替换显示实现做对比。

曾调研引入三方终端控件替代手戳渲染，结论如下：

| 方案 | 结论 |
|------|------|
| ohpm 原生 ArkTS 终端组件 | 不存在（生态位空白） |
| xterm.js + ArkWeb（WebView） | 唯一经验证方案，但需 JS 桥传输、软键盘兼容性未知、引入独立渲染面 |
| Flutter + xterm.dart | 需放弃整个 ArkTS 架构重写 |
| 自研 ArkTS Canvas 渲染 | 无参考、工作量大 |

## 决策（2026-07-21）

**继续采用现有原生 Text/Span 方案**，不引入 WebView。理由：WebView 方案数据需经 JS 桥
（base64 + runJavaScript）、软键盘与 xterm 内置 textarea 兼容性未验证、Web 为独立渲染面
与 ArkUI 交互隔离，代价高于收益。

**但保留可替换性**：将终端显示抽取为独立组件并定义抽象接口，将来随时可换控件。

## 目标

1. 把终端显示（输出渲染 + 输入条 + 隐藏输入框）从 TerminalPage 抽取为独立组件
   `components/TerminalNativeView.ets`。
2. 定义显示组件抽象契约 `components/TerminalDisplayContract.ets`（TerminalViewController
   命令式桥 + 统一 props/回调签名），未来新增显示实现只需遵循同一契约即可挂载切换。
3. TerminalPage 瘦身为编排层：连接生命周期、工具条共享逻辑、粘贴、键盘状态、导航避让。

## 平台需求

- HarmonyOS NEXT（ArkTS Stage 模型），模拟器 x86_64 + 真机 arm64。

## 关键流程

- 数据流（输出）：Rust 会话线程发 `output` 事件（整屏文本快照）→ 显示组件订阅并整体替换渲染。
- 数据流（输入）：显示组件经 `onInput` 回调交父级写入会话。
- Resize：显示组件经 `onResize` 回调交父级同步 PTY（父级按连接态门控）。
- 工具条按键：CTRL/ALT/KBD/PAST 为页面级共享逻辑；其余经 TerminalViewController
  转发给当前显示组件。

## 非目标

- 不引入 WebView / xterm.js（已评估放弃）。
- 不改动 SSH 后端（libssh2）与 Rust 终端解析逻辑。
- 不改动服务器列表页、网络诊断页等其他页面。

## 待澄清

- 无。
