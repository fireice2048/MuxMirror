# BugFix 记忆：鸿蒙终端状态栏底部留白

## 现象

- 触发条件：HarmonyOS 原生终端连接 tmux/rmux 等备用屏 TUI。
- 用户影响：状态栏与终端容器底部之间叠加出约数行黑色空白，与电脑原始终端差异明显。

## 根因

- ArkTS 计算 PTY 高度时额外少报一行，同时 Scroll 上下各保留 `12vp` 内边距。
- Rust 备用屏快照在最后一行后固定追加 `\n`，ArkUI `Text` 将其渲染为额外空白行。
- 三部分留白叠加后，使状态栏明显上浮。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/components/TerminalNativeView.ets`、`MobileApp/shared/src/terminal/mod.rs`。
- 关键改动：PTY 行数按扣除顶部内边距后的真实高度计算；Scroll 底部内边距改为 0；备用屏快照仅保留行间换行，移除最后一行后的尾随换行。

## 验证方式

- 复现步骤：模拟器连接 M5 Pro，进入 RMUX `ahs` TUI，对照状态栏与终端容器底部位置。
- 验证命令：`cd MobileApp/shared && cargo test`；`bash scripts/deploy-harmony-all.sh`。
- 验证结果：67 个 Rust 测试通过；双 ABI 和 HAP 构建成功；模拟器覆盖安装并启动成功；截图确认状态栏贴近底部，顶部内容未下移且未新增折行。部署脚本本轮未识别到真机。

## 预防措施

- PTY 行数、Scroll 内边距和快照尾随换行都会占用垂直行高，调整时必须合并计算，不能分别增加安全余量。
- 备用屏快照应以可见字符结束；光标定位所需空白保留在行内，不使用末尾换行制造额外行。
