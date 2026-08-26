# 移动端 MUX client 隔离需求

## 背景

手机与电脑端同时 attach 同一个 tmux session 时，会共同向同一个 pane shell 输入。若手机在该 shell 中执行未指定 `-c target-client` 的 `switch-client`，tmux 无法从命令本身识别输入来自哪个 client，可能把电脑端 client 切换到另一 session。电脑端原 session 若启用了 `destroy-unattached`，最后一个 client 离开后会立即销毁 session，并终止其中正在执行的 Codex 等任务。

## 目标

- 移动端导航不得切换、detach 或销毁任何无法明确证明属于当前手机 SSH PTY 的 MUX client。
- 每次从导航进入 tmux/rmux session，都使用新建的普通 SSH PTY 执行一次 `attach-session -f ignore-size`。
- 若 attach 命令发现当前 shell 已在 tmux 或 rmux 内，必须安全拒绝，不能回退到无目标 client 的 `switch-client`。
- Android、iOS、HarmonyOS 三端保持相同安全语义。

## 平台需求

- 页面离开现有终端时先关闭手机自己的 SSH session；进入所选 MUX 页面时建立新的 SSH session。
- attach 命令同时检查 `TMUX`、`RMUX_SESSION` 和 `RMUX`，任一存在都视为生命周期异常。
- 普通 SSH shell 使用 `exec <mux> attach-session -f ignore-size -t <session>`，session 名继续进行 POSIX shell 安全引用。
- 禁止生成无 `-c target-client` 的 `switch-client` 命令。

## 关键流程

1. 用户离开当前手机终端，App 关闭其 SSH PTY。
2. 导航页通过独立 exec 通道查询 MUX session。
3. 用户选择目标后，App 创建新的 SSH PTY。
4. 新 PTY 连接成功后执行一次安全 attach 命令。
5. 若检测到任一 MUX 环境变量，命令输出错误并停止，不操作任何现有 client。

## 非目标

- 本次不实现同一 SSH PTY 内的快速 MUX 切换。
- 本次不修改电脑端 `destroy-unattached` 策略。
- 本次不改变服务端 MUX JSON 协议或导航页面布局。

## 验收标准

- 三端生成的 attach 命令不包含 `switch-client`。
- tmux 和 rmux session 名包含单引号时仍能安全引用。
- 两个 client 同时 attach 同一测试 session 时，手机选择其他 session 不改变电脑端 client 的 session。
- 手机断开后，电脑端原 session 及其中任务继续存在。

## 待澄清问题

- 若未来需要无重连快速切换，必须先设计可由独立控制通道验证的手机 client 标识，再单独评审。
