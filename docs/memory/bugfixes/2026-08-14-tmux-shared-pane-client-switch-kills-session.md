# BugFix 记忆：共享 pane 误切桌面 client 导致任务会话被销毁

## 现象

- 触发条件：电脑端与手机同时 attach 一个 tmux session，手机随后通过导航进入另一个 session。
- 用户影响：原电脑终端标题仍显示旧 session，但实际 client 被切到另一 session；原 session 从 `tmux ls` 消失，其中正在执行的 Codex 任务被终止。该问题已重复发生。

## 根因

- 手机生成了未指定 `-c target-client` 的 `tmux switch-client -t <session>`。
- 手机和电脑 attach 同一个 session 时共享 pane shell；命令在 pane 中执行后，tmux 无法知道输入来自哪个 client，会选择当前或最近活跃 client，可能命中电脑端。
- 自动创建的桌面 session 在 `client-attached` hook 中启用 `destroy-unattached=on`。电脑 client 被误切走、手机随后断开后，原 session 没有 client，tmux 立即销毁它。
- 仅检查 `$TMUX` 只能区分普通 shell 与 MUX shell，不能区分共享 pane 中的手机 client 和电脑 client。

## 修复方案

- 涉及模块：HarmonyOS、Android、iOS 终端 attach 命令及三端回归测试。
- 关键改动：删除移动端生成命令中的 `switch-client`；新建普通 SSH PTY 才允许执行 `exec attach-session -f ignore-size`；检测到 tmux/rmux 环境时直接拒绝。
- 同步纠正 2026-08-14 最近需求与 memory 中“已在 MUX 内使用 switch-client”的错误约束。

## 验证方式

- 复现步骤：隔离 tmux server 中创建两个 client 同时 attach `source`，从共享 pane 执行无 `-c` 的 `switch-client -t destination`，可观察其中一个 client 被切走。
- 验证命令：三端单元测试、HarmonyOS 构建，以及隔离双 client 人工回归。
- 验证结果：Android JVM 单测通过；iOS `TermirrorTests` 5 项通过；HarmonyOS Hvigor 单测与 `devecocli build` 通过。隔离双-client 测试中，安全命令执行前后两个 client 均留在 `source`；断开其中一个 client 后，启用 `destroy-unattached` 的 `source` 仍保留且桌面 client 继续 attached。签名 HAP 已覆盖安装到 Pura 90 Pro 模拟器并稳定启动。

## 预防措施

- 不从共享 pane 执行无法明确定位手机 client 的生命周期命令。
- 安全测试必须断言生成命令不包含 `switch-client`，不能只验证环境变量分支存在。
- 若未来实现快速切换，必须通过独立控制通道保存并验证手机 SSH TTY，再显式使用 `-c target-client`。
