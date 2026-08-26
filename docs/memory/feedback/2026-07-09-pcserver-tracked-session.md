# 反馈记忆：PCServer tracked 会话联调依赖真实 macOS 终端

## 坑点描述

- `list_windows` / `list_tabs` / `read_screen`（tracked macOS 终端）**只在 `list_windows` 的 session 是 tracked 且 `terminal_id` 有效时才有意义**，返回的是电脑端系统终端 App（Terminal.app / iTerm2）的窗口/标签页。
- 在非交互 shell（CI、SSH 无 TTY）里运行 `attach register` 拿不到 `TERM_PROGRAM` / `tty`，**无法创建 tracked session**，导致 `list-windows <sid>` 返回 `unknown session` 或空数据。
- `spawn-pty` 走的是 managed PTY，与 tracked 终端窗口无关，`list_windows` 对其返回 `unsupported_operation`。

## 触发条件

- 想在 macOS 上联调窗口/标签页查询，但在非交互环境直接 `attach register` + `attach list-windows`。
- 想在手机/模拟器跨设备连本机 PCServer，但未做端口转发/同网段，且手机侧无真实终端的 tracked session。

## 正确做法

- 联调窗口列表：在**真实 Terminal.app / iTerm2** 里运行 `attach track`（后台跟踪当前终端），得到 tracked session；或在 App 侧 `register` 时填 `kind=Tracked, terminal_id="mobile-client"` 让服务端走 adapter 全局列出窗口。
- 跨设备连通：手机/模拟器需通过 SSH 端口转发或同网段访问电脑 `127.0.0.1:47631`，并用 `attach auth-info` 获取 token 填入 `ServerConfig.token`。
- 纯协议链路验证可用 Rust CLI：`attach hello` / `attach auth-info` / `attach register`（真实终端下）/ `attach list-windows <sid>`。

## 验证方式

- 在真实 macOS 终端执行 `attach track` 后另开窗口 `attach list-windows $(attach list | ...)`，应能返回窗口分组 JSON。
- 协议 JSON 解析逻辑由 `remote-control-shared` 的 `JsonUtilTest` 单测覆盖。
