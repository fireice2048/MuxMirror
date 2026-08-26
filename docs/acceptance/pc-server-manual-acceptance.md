# PC 服务端人工验收方法

本文用于人工验收当前 `attach` Rust 服务端原型。

## 前置准备

在仓库根目录执行：

```sh
cargo build -p attach
```

验证安装脚本：

```sh
ATTACH_INSTALL_DIR="$(mktemp -d)" ATTACH_BUILD_PROFILE=debug scripts/install-attach.sh
```

预期：输出安装路径，目标目录下存在可执行的 `attach`。

验证发布包脚本：

```sh
ATTACH_DIST_DIR="$(mktemp -d)" scripts/package-attach.sh
```

预期：输出 `.tar.gz` 路径，压缩包内包含 `attach` 和 `README.md`。

为避免影响默认端口，建议使用临时端口：

```sh
export ATTACH_SERVICE_ADDR=127.0.0.1:48740
```

验证配置文件：

```sh
CONFIG_FILE="$(mktemp)"
printf '{"service_addr":"127.0.0.1:48739"}' > "$CONFIG_FILE"
ATTACH_CONFIG="$CONFIG_FILE" cargo run -p attach -- hello
ATTACH_CONFIG="$CONFIG_FILE" cargo run -p attach -- shutdown
```

预期：`hello` 正常输出协议能力，说明配置文件中的 `service_addr` 生效。

## 1. 验证服务可自动启动

执行：

```sh
cargo run -p attach -- list
```

预期：命令不报错，输出 JSON 数组，例如 `[]`，说明 `attach list` 能自动拉起本机 Attach 服务。

## 2. 验证终端注册

执行：

```sh
cargo run -p attach -- register
cargo run -p attach -- list
```

预期：`list` 输出包含一个终端会话，字段包含 `id`、`pid`、`parent_pid`、`title`、`shell`、`started_at_unix_ms`、`last_seen_unix_ms`。

## 3. 验证后台跟踪模式

执行：

```sh
cargo run -p attach -- track
cargo run -p attach -- list
```

预期：`track` 立即返回，不阻塞当前 shell；`list` 能看到对应终端会话，且包含 `last_seen_unix_ms`。

## 4. 验证默认命令行为

执行：

```sh
cargo run -p attach
cargo run -p attach -- list
```

预期：不带子命令时等价于 `track`，命令立即返回，`list` 能看到新注册的终端会话。

## 5. 验证多终端汇总

打开 3 个不同终端窗口或标签页，每个终端执行：

```sh
export ATTACH_SERVICE_ADDR=127.0.0.1:48740
cargo run -p attach -- track
```

任意一个终端执行：

```sh
cargo run -p attach -- list
```

预期：JSON 数组里出现多个会话，不同会话的 `pid` / `id` 不同；如果终端环境不同，`title` / `shell` 可能不同。

## 6. 验证 title 覆盖

执行：

```sh
ATTACH_TITLE="AI-Agent-1" cargo run -p attach -- track
cargo run -p attach -- list
```

预期：输出中存在：

```json
"title": "AI-Agent-1"
```

## 7. 验证服务地址覆盖

换一个端口执行：

```sh
ATTACH_SERVICE_ADDR=127.0.0.1:48741 cargo run -p attach -- list
```

预期：命令正常输出，不影响 `48740` 端口上的服务数据，说明 `ATTACH_SERVICE_ADDR` 覆盖生效。

## 8. 验证授权信息输出

执行：

```sh
cargo run -p attach -- auth-info
```

预期：输出 JSON 对象，字段包含 `protocol_version`、`endpoint`、`token`、`user`；`endpoint` 与当前 `ATTACH_SERVICE_ADDR` 一致，`token` 非空。

## 9. 验证协议能力查询

执行：

```sh
cargo run -p attach -- hello
```

预期：输出 JSON 对象，字段包含 `protocol_version` 和 `capabilities`；`capabilities` 至少包含 `hello`、`register`、`heartbeat`、`list_sessions`、`connect_session`、`read_screen`、`send_input`、`resize`、`shutdown`。

## 10. 验证服务状态与平台能力

执行：

```sh
cargo run -p attach -- status
```

预期：输出 JSON 对象，字段包含 `protocol_version`、`platform` 和 `session_count`；`platform.adapters` 至少包含一个 adapter，并清楚列出当前平台能力与限制。Unix 平台上 `supports_tracked_terminal_io` 应为 `true`，但 adapter limitations 会说明 TTY 访问和终端模拟器竞争等约束。

## 11. 验证过期会话清理

启动一次后台跟踪：

```sh
cargo run -p attach -- track
cargo run -p attach -- list
```

找到并杀掉对应后台 `attach daemon` 进程：

```sh
ps aux | grep "attach daemon"
# 将 <daemon_pid> 替换为实际 PID，例如 kill 53708
kill <daemon_pid>
```

等待至少 16 秒后执行：

```sh
cargo run -p attach -- list
```

预期：被杀掉的会话从列表中消失。当前 TTL 约为 15 秒。

## 12. 验证会话连接元数据

执行：

```sh
cargo run -p attach -- register
cargo run -p attach -- list
cargo run -p attach -- connect <session-id>
```

将 `<session-id>` 替换为 `list` 输出中的真实 `id`。

预期：`connect` 输出指定会话的 JSON 元数据，字段包含 `id`、`pid`、`terminal_key`、`last_seen_unix_ms`。

验证 detach：

```sh
cargo run -p attach -- detach <session-id>
cargo run -p attach -- list
```

预期：`detach` 退出码为 0，且会话仍保留在 `list` 输出中。

## 13. 验证日志输出

执行：

```sh
RUST_LOG=debug cargo run -p attach -- track
```

预期：可看到父进程侧的 debug 日志，例如服务已存在。由于 `track` 会将后台 `daemon` 的标准输出和错误输出置空，心跳日志不会直接显示在当前终端；如需观察注册和心跳细节，可临时执行前台命令：

```sh
RUST_LOG=debug cargo run -p attach -- daemon
```

日志中不应包含密码、token、私钥等敏感信息。

## 14. 验证 managed PTY 画面读取

执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "printf attach-screen-ok")
cargo run -p attach -- read-screen "$PTY_ID"
```

预期：`read-screen` 输出包含 `attach-screen-ok`。

## 15. 验证 managed PTY 输入转发

执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "cat")
cargo run -p attach -- send-input "$PTY_ID" $'attach-input-ok\n'
cargo run -p attach -- read-screen "$PTY_ID"
```

预期：`read-screen` 输出包含 `attach-input-ok`。

## 16. 验证 managed PTY 窗口调整

执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "cat")
cargo run -p attach -- resize "$PTY_ID" 120 32
```

预期：`resize` 命令退出码为 0，无错误输出。

## 17. MobileClient 联调前冒烟

执行：

```sh
cargo build -p attach
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- shutdown || true
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- auth-info
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- status
PTY_ID=$(ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- spawn-pty "cat")
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- send-input "$PTY_ID" $'mobile-link-ok\n'
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- read-screen "$PTY_ID"
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- close "$PTY_ID"
ATTACH_SERVICE_ADDR=127.0.0.1:48740 cargo run -p attach -- shutdown
```

预期：`auth-info`、`status` 正常输出 JSON；`read-screen` 输出包含 `mobile-link-ok`。

## 18. 验证 managed PTY 列表与连接

执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "cat")
cargo run -p attach -- list
cargo run -p attach -- connect "$PTY_ID"
```

预期：`list` 输出包含 `$PTY_ID`；`connect` 输出该 managed PTY 的 JSON 元数据，`kind` 为 `managed_pty`，`tab_hint` 为 `managed-pty`。

## 19. 验证会话主动关闭

执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "cat")
cargo run -p attach -- close "$PTY_ID"
cargo run -p attach -- read-screen "$PTY_ID"
```

预期：`close` 退出码为 0；随后 `read-screen` 返回 unknown session 错误。

## 20. 验证 tracked terminal 输入转发

执行：

```sh
cargo run -p attach -- track
SESSION_ID=$(cargo run -p attach -- list | jq -r '.[] | select(.kind == "tracked") | .id')
cargo run -p attach -- send-input "$SESSION_ID" $'tracked-input-ok\n'
```

预期：`send-input` 退出码为 0，无错误输出；如果当前终端 TTY 可被服务访问，输入会被转发到对应终端。由于画面同步受终端模拟器和权限限制，`read-screen` 可能返回空内容或 `unsupported_operation`。

## 21. 验证 macOS Terminal.app / iTerm2 画面同步与输入转发

在 macOS Terminal.app 或 iTerm2 中执行：

```sh
cargo run -p attach -- track
SESSION_ID=$(cargo run -p attach -- list | jq -r '.[] | select(.kind == "tracked") | .id')
cargo run -p attach -- read-screen "$SESSION_ID"
cargo run -p attach -- send-input "$SESSION_ID" $'macos-terminal-ok\n'
cargo run -p attach -- resize "$SESSION_ID" 120 32
```

预期：`read-screen` 返回当前标签页的文本内容；`send-input` 退出码为 0；`resize` 退出码为 0。

对于 Terminal.app，若已授予 `attach` Accessibility 权限（系统设置 > 隐私与安全性 > Accessibility），`send-input` 会通过 `System Events` 发送真实按键；若未授权，CLI 会打印引导日志，服务内部降级为 `do script`，此时输入会作为命令执行并可能污染 shell 历史。若终端未授权 AppleScript 控制，命令可能返回 `macos_terminal_error`。

### 21.1 验证标签页顺序变化后仍能命中

在同一 Terminal.app 窗口中打开两个标签页，在被跟踪标签页执行：

```sh
cargo run -p attach -- track
SESSION_ID=$(cargo run -p attach -- list | jq -r '.[] | select(.kind == "tracked") | .id')
```

拖动被跟踪标签页到另一个位置（改变 tab-index），然后执行：

```sh
cargo run -p attach -- send-input "$SESSION_ID" $'after-move-ok\n'
```

预期：`send-input` 退出码为 0，输入仍被转发到原标签页。

### 21.2 验证标签页关闭后 session 被清理

关闭被跟踪标签页，然后执行：

```sh
cargo run -p attach -- list
```

预期：被关闭标签页对应的 `tracked` session 从列表中消失，或在下一次 `read-screen` / `send-input` 时返回 `unknown_session`。

### 21.3 验证高频操作稳定性

在 macOS Terminal.app 或 iTerm2 中执行：

```sh
cargo test -p attach macos_terminal_high_frequency_operations_are_stable -- --nocapture
```

预期：测试通过或被跳过（若不在 Terminal.app / iTerm2 中）。测试会连续 50 次 `read-screen` 并执行 10 轮 `send-input` + `read-screen`，验证 adapter 绑定与 session 不会泄漏。

## 22. 验证标签页切换

在 macOS Terminal.app 或 iTerm2 中打开多个标签页，执行：

```sh
cargo run -p attach -- track
SESSION_ID=$(cargo run -p attach -- list | jq -r '.[] | select(.kind == "tracked") | .id')
cargo run -p attach -- list-tabs "$SESSION_ID"
OTHER_TAB=$(cargo run -p attach -- list-tabs "$SESSION_ID" | jq -r '.[1].terminal_id')
cargo run -p attach -- switch-tab "$SESSION_ID" "$OTHER_TAB"
cargo run -p attach -- read-screen "$SESSION_ID"
```

预期：`list-tabs` 输出多个标签页；`switch-tab` 退出码为 0；切换后 `read-screen` 返回新标签页的内容。

## 23. 验证 Windows ConPTY managed PTY

在 Windows 10 1809+ 环境中执行：

```sh
cargo run -p attach -- spawn-pty "echo windows-pty-ok"
```

预期：输出 `pty-...` 形式的 session id。

然后执行：

```sh
PTY_ID=$(cargo run -p attach -- spawn-pty "echo windows-pty-ok")
cargo run -p attach -- read-screen "$PTY_ID"
cargo run -p attach -- send-input "$PTY_ID" "windows-input-ok\r\n"
cargo run -p attach -- resize "$PTY_ID" 120 32
cargo run -p attach -- close "$PTY_ID"
```

预期：`read-screen` 输出包含 `windows-pty-ok`；`send-input` 退出码为 0；`resize` 退出码为 0；`close` 后该 session id 不可再读取。

## 24. 清理验收环境

## 25. 验证服务重启恢复

执行：

```sh
cargo run -p attach -- track
cargo run -p attach -- list
cargo run -p attach -- shutdown
sleep 6
cargo run -p attach -- list
```

预期：`shutdown` 后下一次 `list` 会自动拉起服务；原后台 daemon 在下一次心跳时自动重新注册，`list` 中再次出现 `tracked` 会话。

## 26. 验证旧 daemon 清理

执行：

```sh
cargo run -p attach -- track
cargo run -p attach -- track
sleep 6
ps aux | grep "attach daemon"
cargo run -p attach -- list
```

预期：同一终端重复 `track` 后，列表中同一个 `terminal_key` 只保留最新会话；旧 daemon 在收到 `superseded_session` 后退出，不持续发送心跳。

## 27. 清理验收环境

优先使用服务端优雅退出命令：

```sh
cargo run -p attach -- shutdown
```

如果服务无响应，再查找并结束测试服务：


```sh
lsof -ti tcp:48740 | xargs kill
lsof -ti tcp:48741 | xargs kill
```

如 `lsof` 不可用，可用：

```sh
ps aux | grep attach
kill <pid>
```

如果仍看到残留的 `attach service`，先确认端口再清理：

```sh
lsof -Pan -p <service_pid> -i
kill <service_pid>
```

开发验收环境中也可以按命令名一次性清理当前仓库的测试进程：

```sh
pkill -f "/target/debug/attach (service|daemon)"
```

注意不要在有真实业务会话时使用批量清理命令。

## 通过标准

- `attach list` 可自动启动服务。
- `attach register` 可注册当前终端。
- `attach track` 和默认 `attach` 都能立即返回。
- 多终端能被统一汇总。
- `ATTACH_TITLE` 能覆盖 title。
- `ATTACH_SERVICE_ADDR` 能隔离不同服务实例。
- `attach auth-info` 能输出服务 endpoint 和 token。
- `attach hello` 能输出协议版本和能力列表。
- `attach status` 能输出平台 adapter 能力、限制和活跃会话数。
- `attach connect <session-id>` 能输出指定会话元数据。
- `attach detach <session-id>` 能结束接管且不关闭会话。
- `attach spawn-pty` 后可通过 `attach read-screen` 读取 managed PTY 输出。
- `attach send-input` 后可通过 `attach read-screen` 读取 managed PTY 输入回显。
- `attach resize` 能调整 managed PTY 窗口大小且不报错。
- managed PTY 会出现在 `attach list`，并可通过 `attach connect` 查看元数据。
- `attach close` 能主动关闭 managed PTY，会话关闭后不可再读取。
- `attach track` 注册的 tracked session 在 Unix 上尝试携带 `tty_path`；`attach send-input` 对可访问 TTY 的 tracked session 能转发输入且不报错。
- macOS 上 `attach track` 注册的 tracked session 尝试携带 Terminal.app / iTerm2 标签页标识；`attach read-screen`、`send-input`、`resize` 在 AppleScript 权限允许时能操作对应终端。
- macOS 上 `attach list-tabs` 能列出可用标签页，`attach switch-tab` 能切换会话绑定到指定标签页。
- 心跳停止后，会话能在 TTL 后被清理。
- 服务重启后，存活 daemon 能重新注册会话。
- 同一终端重复 `track` 后，旧 daemon 能自动退出。
- 被跟踪终端父进程退出后，对应 daemon 能停止并关闭会话。
- 验收过程中无 panic、无敏感日志、无明显资源异常。
