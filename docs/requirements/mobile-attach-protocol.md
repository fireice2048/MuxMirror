# Attach 移动端集成协议

> 适用范围：MobileClient 通过 SSH 登录电脑后，与本机 `attach` 服务进行 JSON line 通信。
> 服务端实现：`PCServer/attach`

## 1. 传输与鉴权

### 1.1 传输格式

- 每个请求和响应均为**一行 JSON**，以 `\n` 结束。
- 编码：UTF-8。
- 连接：TCP，默认 `127.0.0.1:47631`。
- 当前为**请求-响应模型**：客户端发送一行请求，服务端返回一行响应后关闭连接。如需实时通知，客户端需主动轮询。

### 1.2 SSH 后服务发现

Mobile 端通过 SSH 在目标电脑上执行：

```sh
attach auth-info
```

输出示例：

```json
{
  "protocol_version": 1,
  "endpoint": "127.0.0.1:47631",
  "token": "a1b2c3d4e5f6...",
  "user": "alice"
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `protocol_version` | 当前协议版本 |
| `endpoint` | 本机服务地址 |
| `token` | 鉴权令牌 |
| `user` | 当前系统用户 |

### 1.3 请求鉴权

所有协议请求外层必须包含 `token` 和 `request`：

```json
{
  "token": "a1b2c3d4e5f6...",
  "request": {
    "type": "list_windows",
    "session_id": "terminal-12345"
  }
}
```

服务端校验 `token` 与 `~/.attach/token` 是否一致。不一致返回：

```json
{
  "type": "error",
  "code": "unauthorized",
  "message": "unauthorized attach request"
}
```

## 2. 能力发现

连接后建议先调用 `hello` 和 `status`，确认服务端能力：

### 2.1 hello

请求：

```json
{ "type": "hello" }
```

响应：

```json
{
  "type": "hello",
  "protocol_version": 1,
  "capabilities": [
    "hello", "register", "heartbeat", "list_sessions", "spawn_pty",
    "connect_session", "detach_session", "read_screen", "send_input",
    "resize", "close_session", "shutdown", "status", "tracked_terminal_io",
    "switch_tab", "list_windows", "list_window_tabs"
  ]
}
```

### 2.2 status

请求：

```json
{ "type": "status" }
```

响应：

```json
{
  "type": "status",
  "protocol_version": 1,
  "platform": {
    "os": "macos",
    "adapters": ["terminal_app", "iterm2"]
  },
  "session_count": 3
}
```

## 3. 查询终端窗口与标签页

仅对 macOS 上 `TERM_PROGRAM` 为 `Apple_Terminal` 或 `iTerm.app` 的 **tracked session** 可用。其他平台或 managed PTY 返回 `unsupported_operation`。

### 3.1 查询所有窗口及其标签页

请求：

```json
{
  "type": "list_windows",
  "session_id": "terminal-12345"
}
```

响应：

```json
{
  "type": "windows",
  "session_id": "terminal-12345",
  "windows": [
    {
      "window_id": "1",
      "title": "Window 1",
      "tabs": [
        { "terminal_id": "1:1:/dev/ttys001", "title": "tab one" },
        { "terminal_id": "1:2:/dev/ttys002", "title": "tab two" }
      ]
    },
    {
      "window_id": "2",
      "title": "Window 2",
      "tabs": [
        { "terminal_id": "2:1:/dev/ttys003", "title": "tab three" }
      ]
    }
  ]
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `window_id` | 窗口标识。Terminal.app 为 `id of window`；iTerm2 为 `unique id of window` |
| `title` | 窗口标题（当前为占位，格式 `Window {window_id}`，后续可优化为真实标题） |
| `tabs` | 该窗口内的标签页列表 |
| `terminal_id` | 标签页唯一标识，用于 `read_screen` / `send_input` / `resize` / `switch_tab` |

### 3.2 查询单个窗口的标签页列表

请求：

```json
{
  "type": "list_window_tabs",
  "session_id": "terminal-12345",
  "window_id": "1"
}
```

响应：

```json
{
  "type": "window_tabs",
  "session_id": "terminal-12345",
  "window_id": "1",
  "tabs": [
    { "terminal_id": "1:1:/dev/ttys001", "title": "tab one" },
    { "terminal_id": "1:2:/dev/ttys002", "title": "tab two" }
  ]
}
```

### 3.3 切换到指定标签页

Mobile 端进入某个标签页前，可通知服务端把 tracked session 绑定切换到该标签页：

请求：

```json
{
  "type": "switch_tab",
  "session_id": "terminal-12345",
  "terminal_id": "1:2:/dev/ttys002"
}
```

响应：

```json
{
  "type": "switched_tab",
  "session_id": "terminal-12345",
  "terminal_id": "1:2:/dev/ttys002"
}
```

切换后，对该 session 的 `read_screen` / `send_input` / `resize` 均作用于新标签页。

## 4. 新建/关闭窗口与标签页通知

> **当前实现状态**：服务端当前为请求-响应模型，没有 server-push 通知通道。以下方案为推荐客户端行为。

### 4.1 检测新建或关闭

客户端通过**定时轮询** `list_windows` 获取最新窗口与标签页状态，与本地缓存对比：

- 出现新的 `window_id` → 新建窗口
- 某个 `window_id` 消失 → 窗口关闭
- 某窗口内出现新的 `terminal_id` → 新建标签页
- 某窗口内某个 `terminal_id` 消失 → 标签页关闭

建议轮询间隔：进入窗口列表页时 1~3 秒，进入终端页后 3~5 秒，或按业务需求调整。

### 4.2 远程关闭

> **当前实现状态**：服务端目前不支持远程关闭电脑端的单个窗口或单个标签页。

当前可关闭的是 Attach 会话本身：

```json
{
  "type": "close_session",
  "session_id": "terminal-12345"
}
```

响应：

```json
{
  "type": "closed",
  "session_id": "terminal-12345"
}
```

关闭 session 仅结束 Attach 对该终端的跟踪，不会关闭电脑端真实的终端窗口/标签页。

## 5. 读取终端数据流

终端画面通过**轮询读取**获取。

### 5.1 read_screen

请求：

```json
{
  "type": "read_screen",
  "session_id": "terminal-12345"
}
```

响应：

```json
{
  "type": "screen",
  "session_id": "terminal-12345",
  "content": "...终端当前屏幕内容..."
}
```

说明：

- 对 tracked macOS 终端，返回当前标签页的屏幕内容。
- 对 managed PTY，返回 PTY 的 screen buffer。
- macOS Terminal.app / iTerm2 画面读取带有 200ms 短期缓存，高频轮询时不会反复调用 AppleScript。

### 5.2 终端页刷新策略

建议：

- 用户进入终端页后，以 200~500ms 间隔轮询 `read_screen`。
- 检测到内容变化时刷新 UI。
- 用户离开终端页后停止轮询，减少服务端与 AppleScript 开销。

## 6. 发送按键指令

### 6.1 send_input

请求：

```json
{
  "type": "send_input",
  "session_id": "terminal-12345",
  "input": "ls -la\n"
}
```

响应：

```json
{
  "type": "input_accepted",
  "session_id": "terminal-12345"
}
```

说明：

- `input` 为原始字符串，可包含特殊字符：
  - `\n`：回车
  - `\t`：Tab
  - `\u001b`：Escape
- macOS Terminal.app：有 Accessibility 权限时发送真实按键；无权限时降级为 `do script`，会污染 shell 历史。
- iTerm2：通过 AppleScript `write text` 写入。
- managed PTY：直接写入 PTY stdin。

### 6.2 软键盘映射示例

| 按键 | input 内容 |
|------|------------|
| 回车 | `\n` |
| Tab | `\t` |
| Esc | `\u001b` |
| Ctrl+C | `\u0003` |
| 方向键上 | `\u001b[A` |
| 方向键下 | `\u001b[B` |
| 方向键右 | `\u001b[C` |
| 方向键左 | `\u001b[D` |

## 7. 调整终端尺寸

请求：

```json
{
  "type": "resize",
  "session_id": "terminal-12345",
  "cols": 120,
  "rows": 32
}
```

响应：

```json
{
  "type": "resized",
  "session_id": "terminal-12345",
  "cols": 120,
  "rows": 32
}
```

建议：Mobile 端根据屏幕尺寸和字体大小计算合适 `cols` / `rows`，在进入终端页或旋转屏幕时调用。

## 8. 错误码

| 错误码 | 含义 |
|--------|------|
| `unauthorized` | token 不匹配 |
| `invalid_request` | 请求 JSON 无法解析 |
| `unknown_session` | 服务端不存在该 session；服务重启后客户端需重新注册 |
| `superseded_session` | 同一 `terminal_key` 已有新会话，旧 daemon 应退出 |
| `unsupported_operation` | 目标 session 存在，但该能力在当前 adapter 上不可用 |
| `macos_terminal_error` | macOS AppleScript 调用失败 |
| `pty_error` | PTY 后端操作失败 |

错误响应格式：

```json
{
  "type": "error",
  "code": "unsupported_operation",
  "message": "list_windows only supported for tracked sessions"
}
```

## 9. 完整交互流程示例

```
1. SSH 登录电脑
2. attach auth-info                    → 获取 endpoint + token
3. TCP 连接 endpoint
4. hello / status                      → 能力发现
5. list_sessions                       → 列出活跃 session
6. list_windows {session_id}           → 获取窗口与标签页
7. switch_tab {session_id, terminal_id} → 绑定到目标标签页
8. 循环：
   - read_screen {session_id}          → 读取画面
   - send_input {session_id, input}    → 发送按键
   - resize {session_id, cols, rows}   → 尺寸变化时调用
9. close_session {session_id}          → 结束跟踪（可选）
```

## 10. 当前限制与后续方向

- **通知机制**：当前无 server-push，客户端需轮询 `list_windows` 检测窗口/标签页变化。后续可考虑长连接或 WebSocket 推送。
- **远程关闭**：当前不支持远程关闭电脑端单个窗口/标签页，仅支持关闭 Attach session 跟踪。
- **窗口标题**：当前 `WindowInfo.title` 为占位值，后续可从 AppleScript 获取真实窗口标题。
- **平台支持**：窗口/标签页查询仅 macOS Terminal.app / iTerm2；Windows / Linux 被跟踪终端暂无窗口分组概念。
