# BugFix 记忆：鸿蒙 MUX 底部视口校正回归

## 现象

- 触发条件：鸿蒙模拟器进入高度大于手机 PTY 的 tmux 会话（现场为 `tab-31`）。
- 用户影响：tmux 状态栏可见，但其上方的 Codex 输入区和最后几行正文不在手机快照内，本地滚动也无法找回。

## 根因

- `attach-session -f ignore-size` 只阻止手机客户端参与共享窗口尺寸计算，不保证小客户端默认看到大窗口底部。
- 2026-08-12 重构安全 attach 命令时，原先按当前 SSH tty 重试执行 `refresh-client -D` 的逻辑被遗漏，代码注释仍声称会校正底部 viewport，形成实现与说明不一致的回归。
- 软键盘压缩 ArkUI 窗口时，布局自身产生的滚动会触发 `onScrollStart` / `onDidScroll`，被误判为用户主动上翻；延迟滚底任务再次检查 `followOutput` 后放弃执行，使已经存在于本地快照的输入区仍停在可视区域下方。

## 修复方案

- 涉及模块：`TerminalPage.ets`、ArkTS 单元测试、终端保真需求文档。
- 关键改动：普通 SSH shell attach 前保存自身 tty，手机客户端注册后的 2 秒内重复对该 tty 执行 `refresh-client -D 999`，再以 `exec attach-session -f ignore-size` 进入目标会话。
- 保留安全边界：不生成 `switch-client`；检测到任一 MUX 环境时继续拒绝 attach；viewport 校正显式指定手机 tty，不操作电脑端 client。
- 本地 Scroll 只在收到真实触摸移动时暂停跟随；布局压缩不再冒充用户滚动。真实触摸会取消待执行定时器，因此布局变化排队的滚底任务无需再次读取可能被布局事件短暂改写的 `followOutput`。

## 验证方式

- 复现步骤：在电脑端保持较高窗口 attach `tab-31`，从鸿蒙模拟器导航进入同一会话，观察状态栏上方输入区和末行。
- 验证命令：`devecocli build clean`、`devecocli build --build-mode debug`、`devecocli check lint --incremental`、签名 HAP 覆盖安装、DevEco UI 点击/滑动/截图及 `tmux list-clients`。
- 验证结果：clean 后 debug 构建及后续增量构建均通过；签名 HAP 已覆盖安装到 Pura 90 Pro 模拟器和 HUAWEI Pura 70 真机。两台设备上的 `tab-31` 均能看到 Codex 输入框、模型/思考状态页脚、最后几行正文和 tmux 状态栏；模拟器键盘显示期间人工滑动可以上翻并重新回到底部。`tmux list-clients` 显示电脑 client 保持 `164x50`，模拟器 client 保持 `43x37 ignore-size`，共享 window 为 `164x49`，未被手机尺寸重排。DevEco 增量 lint 为 0 error / 0 warning（仅报告既有启动图标尺寸 suggestion）。

## 预防措施

- attach 命令测试除断言 `ignore-size` 和禁止 `switch-client` 外，还必须断言通过当前 tty 生成底部 viewport 校正命令。
- 修改跨平台 MUX attach 逻辑时，对照三项独立行为：共享窗口尺寸隔离、client 生命周期隔离、手机客户端 viewport 位置。
