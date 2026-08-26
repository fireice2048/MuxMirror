# 进度：终端显示组件抽象与原生方案重构

需求文档：`docs/requirements/2026-07-21-xterm-web-terminal.md`
分支：`feature/xterm-web-terminal`

## 决策

- 放弃 xterm.js + ArkWeb（WebView）方案，继续采用原生 Text/Span 方案。
- 保留 TerminalView 抽象接口，将来可随时替换显示控件。

## 里程碑

- [x] 需求文档 + 进度文档
- [x] 抽取原生终端显示组件
  - [x] `components/TerminalDisplayContract.ets`（TerminalBackend + TerminalViewController）
  - [x] `components/TerminalNativeView.ets`（输出渲染 + 输入条 + 隐藏输入框 + 硬件键/IME 处理）
  - [x] TerminalPage 瘦身为编排层
  - [x] 模拟器回归验证（连接/输出/输入/命令执行）
- [x] 清理 WebView 方案（删除 rawfile/terminal 资产、回退 rawOutput 事件与 base64 工具）

## 已放弃（记录备查）

- [ ] ~~M1 Rust rawOutput 事件~~（仅服务 xterm.js，已回退）
- [ ] ~~M3 xterm.js + ArkWeb TerminalWebView~~（方案放弃）
- [ ] ~~M4 双后端运行时切换~~（无第二后端，暂不需要；抽象接口已就位）
