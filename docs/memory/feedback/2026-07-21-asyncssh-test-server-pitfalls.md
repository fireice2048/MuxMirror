# 问题排查记忆：asyncssh 搭建 SSH 自测服务器的三个坑

## 现象

- 用 asyncssh 在本机起测试 SSH 服务器验证鸿蒙 App 终端功能时：
  1. App 连接后立刻报 `读取失败：transport read`（libssh2 -43 SOCKET_RECV）；
  2. 终端里每条命令回显两遍；
  3. 输入的字符没有即时回显（行缓冲）。

## 根因

1. **resize 异常杀连接**：App 连接后会发 window-change（pty_size）。asyncssh 把 `TerminalSizeChanged` 以异常形式投递到 `process.stdin.read()`，它不是 `asyncssh.Error` 子类，未被捕获的异常逃逸出 process_factory 后 asyncssh 直接关闭整个连接 → 客户端 recv 返回 0 → libssh2 报 SOCKET_RECV(-43)。注意 libssh2 的 transport.c 里 `nread <= 0` 且非 -EAGAIN 都报 -43，**对端正常 FIN 也是这个错**，别只往"传输错误"想。
2. **line_editor 默认开启**：asyncssh 服务端 `create_server` 默认 `line_editor=True`，对客户端输入做行缓冲 + 协议层回显（命令显示两遍、\r 被翻译、无逐字符回显）。
3. 定位手段：libssh2-sys 直接调 `libssh2_session_last_error` 拿原始错误码（ssh2 crate 转 io::Error 会丢）；给测试服务器加收发字节日志对比 UI 显示，可快速区分 App bug 与测试桩 bug。

## 修复方案

- `create_server(..., line_editor=False)`；
- `process.stdin.read()` 循环里 `except asyncssh.TerminalSizeChanged: continue`；
- 服务器脚本保留在 `/tmp/termirror_ssh_server.py`（venv：`/tmp/termirror_ssh_venv`），账号 test/test123，绑定 127.0.0.1:2222，模拟器经 10.0.2.2 访问。

## 预防措施

- 自测链路出问题先二分：用最小客户端探针（`MobileApp/shared/examples/ssh_probe.rs`）直连测试服务器，复现不了就是测试桩的问题。
- 测试桩的协议行为（回显、行缓冲、PTY 事件）必须与真实 sshd 对齐，否则会产生大量"幽灵 bug"。
