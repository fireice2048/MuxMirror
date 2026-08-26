# BugFix 记忆：iOS MUX 导航总是进入默认会话

> 2026-08-14 更新：本文原先的“先 switch，失败再 attach”方案会误切其他 client，严重时触发 `destroy-unattached` 销毁正在执行任务的 session，已经废止。当前方案见 `2026-08-14-tmux-shared-pane-client-switch-kills-session.md`。

## 现象

- 触发条件：iOS 从服务器终端点击「MUX...」，选择任意 tmux 导航项。
- 用户影响：列表虽然显示 `tab-8`、`tab-12` 等不同目标，进入终端后却总是
  停留在 SSH 登录脚本自动创建或恢复的默认会话，例如 `tmux-14`。

## 根因

- SSH 登录完成时已经处于 tmux client 内。
- iOS 仍执行 `tmux attach-session -t <目标>`；tmux 拒绝嵌套 attach，并输出
  `sessions should be nested with care, unset $TMUX to force`。
- `muxmirror --mux` 还可能返回只检测到 mux 进程、但无法解析 session 的
  `TMUX[]` 项；这种项没有可用于 `switch-client` 的目标，点击后同样只能停在
  默认会话。
- 旧验收只确认导航页能打开，没有点击两个不同目标并检查状态栏，因而漏测。
- 测试结束时 XCTest 会主动以 `SIGTERM(15)` 关闭被测 App；这是测试清理，不是
  App 崩溃，不能用进程是否继续显示来判断用例是否通过。

## 修复方案

- 涉及模块：`MobileApp/iosApp/Termirror/UI/Pages/TerminalScreen.swift`、
  `MobileApp/iosApp/Termirror/UI/Pages/MuxNavScreen.swift`、
  `MobileApp/iosApp/TermirrorUITests/ServerListUITests.swift`。
- 关键改动：
  - 目标命令先执行 `tmux/rmux switch-client -t <目标>`。
  - 当前不是 mux client 时，`switch-client` 失败，再回退到
    `attach-session -f ignore-size -t <目标>`。
  - 导航页过滤 session 为空的不可定位项，不再展示 `TMUX[]` 可点击行。
  - 新增真实数据 UI 验收：从 M5 Pro 导航依次进入 `tab-8`、`tab-12`，断言终端
    快照分别包含对应状态栏；没有本机 M5 Pro 配置时跳过。

## 验证方式

- 复现步骤：M5 Pro → 终端 → MUX... → `tab-8` → 返回导航 → `tab-12`。
- 验证命令：
  `xcodebuild test -project Termirror.xcodeproj -scheme Termirror -destination
  'platform=iOS Simulator,id=<iPhone 17 Pro UDID>'
  -only-testing:TermirrorUITests/ServerListUITests/testInspectLiveMuxNavigation`
- 验证结果：
  - 修复前两个目标均报嵌套 attach 错误，并停留在自动会话 `tab-16`。
  - 修复后首张终端状态栏为 `[tab-8]`，第二张为 `[tab-12]`，内容也分别对应
    TermHook/Codex 与 OpenCode/Android 任务。

## 预防措施

- MUX 导航验收必须检查至少两个目标的实际状态栏，不能只验证列表或页面跳转。
- 手机导航必须使用新建的普通 SSH PTY attach；若登录脚本意外自动进入 MUX，则安全拒绝并修正登录生命周期，禁止“先 switch，失败再 attach”。
