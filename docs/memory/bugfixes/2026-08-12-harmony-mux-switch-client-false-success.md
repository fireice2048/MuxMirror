# BugFix 记忆：鸿蒙导航点击 MUX 会话后停留在普通 shell

> 2026-08-14 更新：本文原先的“检测 MUX 环境后执行 `switch-client`”方案仍会在多 client 共享 pane 时误切电脑端，已被 `2026-08-14-tmux-shared-pane-client-switch-kills-session.md` 的新建 SSH PTY + fail-closed attach 方案取代。以下内容保留为历史排查记录，不应作为当前实现指导。

## 现象

- 触发条件：鸿蒙 App 通过 SSH 连接电脑，进入导航页并点击一个已 attached 的 tmux 会话，例如 `tab-14`。
- 用户影响：终端打印 attach 命令后仍停留在普通 shell，没有进入目标 tmux 会话，也不显示 tmux 状态栏/标签；电脑端已有 tmux client 还可能被意外切换。

## 根因

- 客户端使用 `tmux switch-client ... || tmux attach-session ...` 同时兼容“登录脚本已自动进入 tmux”和“当前是普通 shell”两种状态。
- `tmux switch-client` 从普通 shell 执行时，可能找到同一 tmux server 上已有的其他 client、成功切换它并返回 0。此时 `||` 后的 `attach-session` 不会执行，手机 SSH PTY 始终没有成为 tmux client。
- 模拟器终端中看似重复的命令尾部是 100 列 PTY 自动换行，不是命令重复发送。

## 修复方案

- 涉及模块：`MobileApp/harmonyApp/entry/src/main/ets/pages/TerminalPage.ets`。
- 关键改动：不再根据 `switch-client` 退出码选择回退路径，改为显式检查 `$TMUX`；只有当前手机 shell 已在 tmux 内才执行 `switch-client`，否则直接执行带 `ignore-size` 的 `attach-session`。RMUX 同步检查 `$RMUX_SESSION`/`$RMUX`。
- 抽取 `buildMuxAttachCommand` 纯函数，并为普通 tmux shell、RMUX 与含单引号 session 名补充 ArkTS 单元测试。

## 验证方式

- 复现步骤：模拟器连接 `10.0.2.2`，进入导航页，点击 `tab-14`。
- 验证命令：`devecocli build clean`、`devecocli build --build-mode debug`、`hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap`；启动稳定后通过 `uitest dumpLayout` 与 `uitest screenCap` 确认。
- 验证结果：clean build 与 ArkTS 编译通过，signed HAP 覆盖安装成功；模拟器重新进入导航页可见 `TMUX[tab-14]`，点击后成功显示 `tab-14` 中的 Codex TUI，底部绿色 tmux 状态栏显示 `[tab-14] 0,0`。设备日志未出现新的 TermirrorCore/TerminalPage 错误。
- 单测说明：已在 `LocalUnit.test.ets` 增加两项回归用例；当前仓库的 CLI Hvigor task 列表没有暴露 local-unit-test 执行任务，因此本次以 clean ArkTS 编译和模拟器端到端验收作为实际执行证据。

## 预防措施

- 不用 MUX 控制命令的退出码推断“当前 PTY 是否已经是 MUX client”；环境标识也不能识别共享 pane 中的输入来源 client。当前实现检测到 MUX 环境时直接拒绝，不再执行 `switch-client`。
- 验收 MUX 导航不能只确认命令已输出，必须确认目标 TUI/状态栏已经出现在手机终端，并检查电脑端其他 client 未被误切换。
