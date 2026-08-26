# SSH 连接后的 Attach 服务授权方案

## 背景

Mobile App 通过 SSH 登录电脑后，需要查询和控制电脑上的 Attach 服务。SSH 只能证明用户可以登录这台电脑，但 Attach 服务仍需要确认后续查询和控制请求是否合法，避免本机其他进程、其他系统用户或误连请求控制终端会话。

## 安全目标

- Attach 服务不直接暴露到公网。
- 每个系统用户只能访问自己的 Attach 服务和终端会话。
- Mobile App 通过 SSH 登录后，必须拿到有效授权信息才能调用 Attach 协议。
- 查询、输入转发、终端控制等请求都必须可校验来源。

## 推荐方案

### 1. 仅监听本机地址

Attach 服务默认只监听本机地址：

```text
127.0.0.1
```

或使用平台本地 IPC：

- Unix Domain Socket
- Windows Named Pipe

服务不接受外部网络直连。非内网访问由用户自行配置 VPN 或 SSH，不属于 Attach 服务职责。

### 2. 基于系统用户隔离

每个系统用户运行自己的 Attach 服务。运行目录放在用户私有路径，例如：

```text
~/.attach/
```

或：

```text
$XDG_RUNTIME_DIR/attach/
```

目录权限应限制为仅当前用户可读写：

```text
0700
```

这样 SSH 登录为 `xpeng` 后，只能访问 `xpeng` 用户下的 Attach 服务。

### 3. 使用 Attach 会话令牌

服务启动时生成随机 token，并保存到用户私有运行目录：

```text
~/.attach/token
```

文件权限应限制为仅当前用户可读写：

```text
0600
```

后续所有 Attach 协议请求都必须携带 token，例如：

```json
{
  "token": "...",
  "request": {
    "type": "list_sessions"
  }
}
```

服务端校验 token 正确后才响应请求。

## Mobile 端连接流程

推荐流程：

```text
Mobile App
  -> SSH 登录电脑
  -> 远端执行 attach auth-info
  -> 获取服务地址和 token
  -> 建立 Attach 控制通道
  -> 每个请求携带 token
  -> Attach 服务校验 token 和用户隔离
```

## `attach auth-info` 命令

已新增命令：

```sh
attach auth-info
```

输出示例：

```json
{
  "protocol_version": 1,
  "endpoint": "127.0.0.1:47631",
  "token": "...",
  "user": "xpeng"
}
```

Mobile App 通过 SSH 执行该命令，拿到 endpoint 和 token 后，再进行终端查询、切换和控制。

## 请求校验要求

以下请求必须携带并校验 token：

- 查询服务器端版本和能力。
- 查询终端会话列表。
- 读取指定终端画面。
- 向指定终端发送输入。
- 调整终端窗口大小。
- 关闭或管理服务端会话。

## 风险与防护

- 防止同机其他用户误连：使用用户私有目录和文件权限隔离。
- 防止恶意本地进程扫描端口：服务只监听本机，并要求 token。
- 防止 token 泄露：token 文件使用 `0600` 权限，不写入日志，不通过错误信息回显。
- 防止公网暴露：服务不监听 `0.0.0.0`，远程访问必须经 SSH/VPN。

## 结论

SSH 负责证明“用户能登录这台电脑”；Attach 服务负责证明“该请求有权控制当前用户的终端”。服务端已实现基础版本：

- 服务默认只监听本机。
- 每个系统用户独立服务。
- 私有 token 文件。
- 所有 Attach 协议请求必须携带 token。
- `attach auth-info` 供 Mobile 端通过 SSH 获取连接信息。
