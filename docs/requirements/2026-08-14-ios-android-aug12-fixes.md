# iOS/Android 复用 8 月 12 日移动端问题修复需求

## 背景

8 月 12 日的提交修复了 MUX 导航重复会话、目录分组标题退化，以及从导航进入 tmux 后仍停留在普通 shell 等问题，但对应修复主要落在 MirrorServer 和鸿蒙 ArkTS 页面。iOS 与 Android 仍保留旧的客户端分组和 attach 命令逻辑。

## 目标

- iOS 与 Android 的 MUX 导航按 `mux + session` 唯一化，避免同一会话被多个 client 重复显示。
- 目录分组优先使用服务端 `--by-directory` 返回的组标题，并在旧服务端响应下保持兼容。
- 从导航选择 MUX 会话时，只允许新建的普通 SSH PTY 执行 `attach-session`；检测到任一 MUX 环境变量时安全拒绝，禁止无明确 client 目标的 `switch-client`。
- 为以上纯逻辑补充 iOS/Android 回归测试。

## 平台范围

- `MobileApp/iosApp/`：SwiftUI 导航解析与终端 attach 命令。
- `MobileApp/androidApp/`：Compose 导航解析与终端 attach 命令。
- 不修改已在共享 Rust 核心中完成的 ECH/DCH/ICH/IL/DL 终端解析；共享核心测试作为回归验证。

## 非目标

- 不重做 iOS/Android 的终端绘制后端或鸿蒙专属宽字符背景层。
- 不改变服务端 MUX JSON 协议和导航交互布局。

## 验收标准

- 同一 `mux + session` 出现多条输入时，两个平台窗口/目录列表及会话选择器均只显示一次。
- `--by-directory` 返回的窗口 `title` 为目录时，目录卡片显示该标题，而不是 session 名或单个 tab 的旧 cwd。
- 普通 shell 进入目标会话使用 `exec attach-session -f ignore-size`；已在任一 MUX 内时拒绝操作；生成命令不含 `switch-client`；session 名含单引号时仍安全引用。
- Android 单元测试、iOS XCTest、Rust 核心测试和两端构建通过。
