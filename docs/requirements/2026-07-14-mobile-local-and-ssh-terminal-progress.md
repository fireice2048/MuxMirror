# 移动端本地终端与 SSH 直连终端进度

## 执行计划

- [x] 记录产品需求、平台边界和非目标。
- [x] 建立平台本地工具接口：Android/iOS Local Shell、HarmonyOS TCP 网络诊断。
- [x] 改造首页：添加平台本地工具入口，并将服务器点击改为直达 SSHPage。
- [x] 按变更后的标准 SSH 需求实现 SSHPage Loading、PTY 读写和输入控制；不再选择 Attach 会话。
- [x] 更新移动端 README 与功能记忆。
- [x] 编译 Android、iOS framework 与 HarmonyOS；在 HarmonyOS 模拟器验证首页入口。

## HarmonyOS 标准 SSH 里程碑

- [x] 固定 libssh2 1.11.1 与 mbedTLS 3.6.3 依赖版本。
- [x] 完成 HarmonyOS arm64-v8a 原生依赖交叉编译和 Kotlin/Native cinterop 编译。
- [x] 将原生依赖构建纳入 Gradle，补齐 x86_64 模拟器 ABI。
- [x] 将列表点击改为标准 SSH Loading 页，完全移除该页面对 `TcpTerminalClient` 的调用。
- [x] 完成 SSH 密码认证、PTY 输出轮询、输入和快捷键写入、关闭清理。
- [x] 全量重打包 HAP，在模拟器连接本机当前局域网地址，验证 TCP 与 SSH 握手并留存页面截图和日志证据。
- [x] 使用有效的本机账号密码完成密码认证、PTY shell 和命令输入端到端验收。
- [x] 更新 README、功能记忆和验收说明。

## 进度记录

- 2026-07-14：建立需求与执行计划，开始检查共享 Compose UI、iOS 挂载和现有 Attach TCP 终端连接实现。
- 2026-07-16：按平台调整首页本地入口：HarmonyOS 显示“网络诊断”并仅接受 `tcp <IPv4> [端口]`；Android/iOS 显示“Local Shell”。已完成 Android Debug、iOS simulator framework 编译，以及 HarmonyOS 全量 HAP 重打包、安装和启动；模拟器首页已显示“网络诊断”。
- 2026-07-16：需求变更为新终端页直接使用标准 SSH，不再使用 Attach 自定义协议；用户确认先完成 HarmonyOS。已完成 libssh2/mbedTLS arm64-v8a 交叉编译及 SSH 会话 cinterop 编译，页面接入与 x86_64 构建待完成。
- 2026-07-16：增加固定版本 Git 子模块与可复用交叉编译脚本，Gradle 链接任务自动构建 arm64-v8a/x86_64 静态库；`publishDebugBinariesToHarmonyApp` 双 ABI 链接通过。
- 2026-07-16：共享 UI 已改为点击服务器直接进入 SSH Loading/终端页；删除旧窗口列表和 Attach 终端页路径。HarmonyOS 实现密码认证、PTY shell、非阻塞读写和会话清理，三端编译通过，待 HAP 实连验收。
- 2026-07-16：修复阻塞式 TCP `connect` 无法被协程超时中断的问题，改为非阻塞连接、`poll` 和 `SO_ERROR`，不可达地址会在 10 秒内返回明确错误。
- 2026-07-16：模拟器对本机当前局域网地址完成 TCP 和标准 SSH 握手，应用进程保持存活且未新增 fault log。原生握手崩溃根因为 mbedTLS AArch64 大数除法调用未正确解析的 `__udivti3`；通过 `MBEDTLS_NO_UDBL_DIVISION` 改用可移植除法路径。当前本机 SSH 服务端确认模拟器保存的口令不正确，密码认证、PTY 与命令输入仍待有效凭据复测。
- 2026-07-17：复测前排查本机 SSH 服务端：sshd 22 端口监听正常、防火墙关闭、`com.apple.access_ssh` 经嵌套 admin 组授权且 `medie` 在 admin 组，服务端无阻断；本机当前为热点网络，验收地址需使用当前局域网 IPv4。模拟器侧发现 Pura 90 Pro 的 7.0.0(26) Beta1 镜像已被删除，改用仅剩的 5.1.0(18) 镜像后 App 白屏；根因为 Compose Multiplatform 渲染依赖 API 20+ 绘图接口，API 18 系统缺失且无降级出图（详见 `docs/memory/feedback/2026-07-17-harmony-emulator-api18-white-screen.md`）。
- 2026-07-17：放弃重建镜像，改从 `~/Library/Huawei/Sdk/system-image/` 找到 7.0.0-B1 镜像实体，用 `Emulator -start "Pura 90 Pro" -imageRoot ~/Library/Huawei/Sdk/system-image` 直接启动模拟器。密码改正后 App 仍报 `-18`：根因最终定位为本机 `/etc/ssh/sshd_config` 的 `AllowUsers medie@100.0.0.0/8 medie@192.168.0.0/24` 按来源 IP 限制登录，模拟器经 `10.0.2.2` 连接时来源为 `127.0.0.1` 不在允许范围，与密码对错无关（本机 `ssh medie@127.0.0.1` 同样被拒，真机经允许网段可正常登录）。追加 `AllowUsers medie@127.0.0.0/8 medie@172.20.10.0/28` 后，模拟器密码认证通过、PTY shell 出现远端提示符，端到端验收完成（截图 `docs/acceptance/evidence/harmony/2026-07-17-ssh-auth-passed/pty-shell.jpeg`，详见 `docs/memory/feedback/2026-07-17-ssh-allowusers-source-restriction.md`）。环境前提已写入 `AGENTS.md`。
