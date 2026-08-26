# BugFix 记忆：HarmonyOS SSH 握手原生崩溃

## 现象

- 触发条件：arm64 HarmonyOS 模拟器与可达的 OpenSSH 服务建立 TCP 后执行 libssh2 handshake。
- 用户影响：页面持续看似停在 Loading，实际应用进程已经因 `SIGSEGV` 退出；仅查看截图容易误判为网络等待。

## 根因

- fault log 栈定位到 `mbedtls_mpi_div_mpi` → `mbedtls_ecdsa_verify_restartable` → libssh2 key exchange。
- 反汇编确认崩溃指令是 `mbedtls_mpi_div_mpi` 调用 `__udivti3@plt`。HarmonyOS/Kotlin Native 共享库运行时未正确解析该 compiler-rt 128 位除法辅助函数，跳转到不可执行低地址。
- 仅关闭 `MBEDTLS_HAVE_ASM` 无效，因为问题不是汇编优化，而是双字长除法路径。

## 修复方案

- 涉及模块：HarmonyOS mbedTLS 交叉编译配置、Kotlin/Native SSH 会话和 C socket bridge。
- 关键改动：AArch64 定义 `MBEDTLS_NO_UDBL_DIVISION`，让 MPI 使用 `mbedtls_int_div_int` 可移植路径；同时用非阻塞 `connect` + `poll` + `SO_ERROR` 提供原生 TCP 超时，并补充不含敏感信息的连接阶段日志。

## 验证方式

- 复现步骤：在模拟器点击指向本机当前局域网 SSH 地址的服务器项。
- 验证命令：用 `llvm-nm` 确认 arm64 `libmbedcrypto.a` 不再引用 `__udivti3`；强制无缓存重链 `libkn.so`；清理 `entry/build` 后重打、安装 HAP。
- 验证结果：最终 `mbedtls_mpi_div_mpi` 反汇编调用 `mbedtls_int_div_int`；模拟器日志出现 `SSH handshake completed`，进程保持存活且没有新增 fault log。随后认证被服务器以错误口令拒绝，说明握手崩溃路径已经越过。

## 预防措施

- 原生崩溃必须同时检查应用 PID、fault log 和未剥离共享库反汇编，不能只依据 UI 停留状态判断。
- 修改静态依赖后使用 `--rerun-tasks --no-build-cache` 强制重链，并清空 `harmonyApp/entry/build`，避免旧原生库被标为 `UP-TO-DATE` 后继续装入 HAP。
- 对 AArch64 密码学依赖升级进行一次真实 SSH 握手回归，并检查最终链接产物是否重新引入 `__udivti3` 调用。
