# 功能记忆：移动端按平台提供本地工具

## 背景

- 需求来源：HarmonyOS 普通应用无法启动本地 shell，原 `ping` 命令会因无法执行 `/system/bin/sh` 而失败。
- 使用场景：用户从首页左下角进入本地工具，在 Android/iOS 执行开发环境允许的单次 shell 命令，或在 HarmonyOS 检查目标 TCP 服务是否可达。

## 关键功能点

- Android 和 iOS 首页入口及页面标题显示为 `Local Shell`。
- HarmonyOS 首页入口及页面标题显示为“网络诊断”。
- HarmonyOS 仅接受 `tcp <IPv4> [端口]`；未填写端口时默认 443。
- 输出保留终端式画布、命令回显、文本选择与复制能力。

## 设计与实现

- 涉及模块：`composeUI` 的共享页面和各平台 `LocalTerminal` actual 实现。
- 核心流程：共享 UI 读取平台提供的标题和输入提示；HarmonyOS 通过 `TcpConnection` 建立并立即关闭 TCP 连接，以连接成功与否显示诊断结果。
- 重要约束：HarmonyOS 不尝试执行 `/system/bin/sh`、`popen` 或 ICMP `ping`；TCP 检测只支持点分十进制 IPv4。iOS 模拟器执行命令时显式使用 `/bin/sh -lc`。

## 验证方式

- 命令：`./gradlew :composeUI:publishDebugBinariesToHarmonyApp`，随后在 `harmonyApp` 执行 `devecocli build clean && devecocli build --build-mode debug`。
- 命令：`./gradlew :androidApp:assembleDebug`。
- 结果：HarmonyOS Debug HAP 已全量重打包、安装并启动；Android Debug 编译通过。

## 后续注意事项

- TCP 建连在共享网络实现中没有独立超时控制；若需要可靠的长时间诊断，应在连接层补充超时与取消机制。
