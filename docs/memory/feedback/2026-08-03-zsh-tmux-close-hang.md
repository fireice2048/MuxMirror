# BugFix 记忆：自动启动 tmux 后关闭终端卡死

## 现象

- 触发条件：在 `.zshrc` 中调用 `start_tmux_once`，每次新开终端后点击关闭标签页或窗口。
- 用户影响：Terminal.app 关闭流程卡死；注释 `start_tmux_once` 后恢复正常，但失去自动创建 tmux 会话能力。

## 根因

- `.zshrc` 以普通子进程方式运行 `tmux attach-session`，进程关系为 `login -> zsh -> tmux client`。Terminal.app 关闭窗口时会先等待登录 shell 及其前台子进程退出，约 10 秒后才销毁 TTY；tmux client 在此之前无法得到 `lost tty`，形成关闭等待。
- 原实现还在 zsh 函数内注册 `EXIT HUP` trap 并同步执行 `tmux kill-session`。zsh 的函数内 `EXIT` trap 会在函数返回时触发，不只在 shell 退出时触发，因此正常 detach 也可能误清理会话或退出外层 shell。
- trap 在确认 `new-session` 成功前注册；并发创建会话撞号时存在误删其他同名会话的风险。

## 修复方案

- 涉及模块：用户 `.zshrc`、用户 `.tmux.conf`、仓库 `README.md` 配置示例。
- 先用 `new-session -d` 原子创建会话，避免并发撞号时给其他会话安装清理逻辑。
- 使用 `exec tmux attach-session` 让 tmux client 直接替换登录 zsh，消除 Terminal.app 等待外层 zsh 子进程的 10 秒宽限期。
- 为自动会话设置 `client-attached` hook：attach 后开启会话级 `destroy-unattached`。仍有手机 client 时会话保留，最后一个 client 离开后由 tmux server 自动销毁。
- 将 `Ctrl-b d` 绑定为先关闭 `destroy-unattached`，再通过 `detach-client -E` 将当前 client 原地替换为带跳过标记的登录 zsh。这样手动 detach 后会话保留、Terminal 也保持可用，且不会立即再次自动进入新 tmux 会话。
- 用户原先注释的 `_cleanup_tmux_on_exit` 代码保留不动，不再用未授权的文档整理删除个人配置。

## 验证方式

- 复现步骤：启用 `start_tmux_once`，用 AppleScript 新建独立 Terminal 测试窗口并请求关闭；另建窗口验证手动 detach。
- 验证命令：查询 Terminal window id/TTY、`ps` 进程关系、`tmux list-sessions` 的 `session_attached`/`destroy-unattached`，并以 `/usr/bin/time osascript ... close window` 测量关闭耗时；使用 `zsh -n ~/.zshrc` 检查语法。
- 验证结果：修复前真实关闭约 10 秒；`exec tmux` 后关闭耗时 0.08 秒，0.3 秒后自动会话已不存在。手动 detach 后 client 原地切换为 `zsh -l`，会话保持 `attached=0 destroy=off`。

## 预防措施

- shell 的 `EXIT`、`HUP` trap 不得同步执行可能等待 IPC/server 的清理命令；尤其不能在 zsh 函数中把 `EXIT` trap 当作全局 shell 退出 hook。
- 资源创建成功前不要注册会删除该资源名称的 trap。
- tmux 会话生命周期优先交给 server 侧选项与 hook 管理，并单独覆盖“普通关闭”“手动 detach”“仍有远程 client”与“最后一个 client 离开”场景。
