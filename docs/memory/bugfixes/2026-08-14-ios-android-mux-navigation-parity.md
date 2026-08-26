# BugFix 记忆：iOS/Android MUX 导航与进入会话逻辑未同步

## 背景

8 月 12 日服务端和鸿蒙端已修复 MUX 多 client 重复、目录组标题退化，以及普通 shell 执行 `switch-client` 误切换其他 client 的问题。iOS 和 Android 仍保留旧客户端解析和 attach 命令，因此同一台电脑被多个终端 attach 时仍会看到重复会话，点击导航项也可能停留在普通 shell。

## 根因

- iOS/Android 以服务端返回的每条 tab 直接构造导航项，没有按 `mux + session` 做跨窗口唯一化。
- 目录模式只使用 tab 的 `cwd` 或标题，没有优先使用 `--by-directory` 返回的窗口 `title`。
- `tmux switch-client`/`rmux switch-client` 从普通 shell 执行时可能切换电脑端已有 client 并返回成功；即使检查 MUX 环境变量，手机与电脑共享 pane 时也无法从 pane shell 判断命令来自哪个 client，无 `-c` 的切换仍可能误切电脑端。

## 修复方案

- 两端解析器维护大小写不敏感的 `mux + session` 集合，窗口、目录和 detached 列表统一去重。
- 目录查询使用服务端分组时以窗口 `title` 作为分组键和显示标题，旧服务端响应仍回退到 tab cwd/title。
- 三端 attach 命令统一改为 fail-closed：检查 `${TMUX-}${RMUX_SESSION-}${RMUX-}`，已在任一 MUX 内就拒绝操作；仅允许新建普通 SSH PTY 执行 `exec attach-session -f ignore-size`，session 名继续使用 POSIX 单引号安全转义。
- Android JVM 单测补充完整 `org.json` 测试实现，避免 Android `org.json` stub 阻断本地解析回归测试。

## 影响范围

- `MobileApp/androidApp/`：Compose MUX 解析、终端 attach 命令和回归测试。
- `MobileApp/iosApp/`：SwiftUI MUX 解析、终端 attach 命令和回归测试。
- `MobileApp/harmonyApp/`：ArkTS attach 命令和回归测试。
- 不改动 8 月 12 日已进入共享 Rust 核心的 ECH/DCH/ICH/IL/DL 解析；该核心逻辑已由两端共同使用。

## 验证方式

- Android 单元测试 5 项通过。
- iOS 单元测试 5 项通过；全量 iOS UI 测试中仅既有现场 MUX 用例因没有真实服务器失败。
- 根 workspace Rust 测试 7 项通过，`MobileApp/shared` Rust 测试 81 项通过。

## 预防措施

- 客户端导航实体是 `mux + session`，不是 attached client；任何兼容旧服务端的解析都必须跨窗口去重。
- pane shell 不携带输入来源 client 的身份；禁止从共享 pane 执行无明确 `-c target-client` 的 `switch-client`、`detach-client` 或其他 client 生命周期命令。
- 移动端选择目标 MUX 时必须新建 SSH PTY；检测到已有 MUX 环境时安全拒绝，不能猜测或选择最近活跃 client。
