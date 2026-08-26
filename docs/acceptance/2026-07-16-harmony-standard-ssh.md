# HarmonyOS 标准 SSH 直连验收记录

## 结论

HarmonyOS 模拟器已验证服务器列表点击后进入 SSH Loading 页，并完成到本机 SSH 服务的 TCP 连接与标准 SSH 握手。修复后的应用进程保持存活，系统 fault log 没有新增崩溃记录。

本轮不能声明完整端到端通过：模拟器保存的 `medie` 账号口令被 macOS OpenDirectory 判定为不正确，因此密码认证返回 libssh2 `-18`，尚未进入 PTY shell。需要在服务器配置中保存有效系统登录密码后复测认证、终端提示符和命令输入。

## 执行环境

- 日期：2026-07-16
- 设备：HarmonyOS Pura 90 Pro 模拟器
- HDC 目标：`127.0.0.1:5555`
- SSH 服务：当前开发机局域网 IPv4 的 22 端口
- 客户端：libssh2 1.11.1 + mbedTLS 3.6.3

局域网 IPv4 由 DHCP 分配，验收前必须重新查询；历史配置地址不可作为固定值写入代码或文档。验收记录不包含密码、私钥或完整个人日志。

## 构建与安装

```sh
cd MobileClient
./gradlew :composeUI:linkDebugSharedOhosArm64 \
  :composeUI:linkDebugSharedOhosX64 \
  :composeUI:publishDebugBinariesToHarmonyApp \
  --rerun-tasks --no-build-cache

cd harmonyApp
rm -rf entry/build
devecocli build --build-mode debug
hdc -t 127.0.0.1:5555 install -r \
  entry/build/default/outputs/default/entry-default-unsigned.hap
```

结果：Kotlin/Native 两个 ABI 重链成功，HAP 构建成功并安装成功。

## 连接证据

脱敏后的关键阶段日志：

```text
opening TCP connection to <host>:22
TCP connection established for <host>:22
SSH handshake completed for <host>:22
SSH 密码认证失败：-18
```

同时检查：

- 应用进程在失败页仍然存活。
- 连接后 fault log 列表没有新增 `cppcrash-com.attach.mobile.harmony`。
- macOS 服务端日志显示 `OpenDirectory - The authtok is incorrect`，确认当前阻断是保存口令不正确，不是网络或协议失败。
- 错误页截图：[password-auth-failed.jpeg](evidence/harmony/2026-07-16-standard-ssh/password-auth-failed.jpeg)。

## 剩余验收

在模拟器服务器配置中更新为有效密码后，重新点击列表项并确认：

- 日志出现密码认证完成与 PTY shell 启动。
- 页面出现远端 shell 提示符，而不是错误页。
- 输入一条无副作用命令能够显示输出。
- 返回服务器列表后连接正常关闭，应用无崩溃。

## 2026-07-17 复测结论

密码改正后仍报 `-18`，最终定位为本机 `/etc/ssh/sshd_config` 的 `AllowUsers medie@100.0.0.0/8 medie@192.168.0.0/24` 按来源 IP 限制登录：模拟器经 `10.0.2.2` 连接时来源为 `127.0.0.1`，不在允许范围，与密码对错无关。追加 `AllowUsers medie@127.0.0.0/8 medie@172.20.10.0/28` 后复测通过：

- 密码认证通过，PTY shell 启动，页面出现远端 shell 提示符（`Last login: ...` + 提示符）。
- 证据截图：[pty-shell.jpeg](evidence/harmony/2026-07-17-ssh-auth-passed/pty-shell.jpeg)。
- 根因分析与排查方法：`docs/memory/feedback/2026-07-17-ssh-allowusers-source-restriction.md`；环境前提已写入 `AGENTS.md`。
- 附带结论：模拟器镜像需 ≥ API 20（本次在 API 18 镜像上验证为全屏白屏），见 `docs/memory/feedback/2026-07-17-harmony-emulator-api18-white-screen.md`。
