# BugFix 记忆：移动端 MUX 终端默认显示顶部裁剪区

## 现象

- Android 模拟器进入较高的 tmux window（如 `tab-15`）后，底部 Codex 输入行/页脚中的 `gpt-5.6-sol ...` 不在快照内，只看到 `[tab-15]` tmux 状态栏。

## 根因

- 移动端使用 `attach-session -f ignore-size`，避免手机 PTY 改写电脑端共享 window 尺寸。
- 但 `ignore-size` 只保护共享尺寸；当共享 window 高于手机 PTY 时，tmux 新 client 默认展示顶部裁剪区域，底部 TUI 内容因此不可见，本地 Compose 滚动无法恢复未发送到客户端的行。

## 修复方案

- Android 和 iOS attach 命令记录当前 SSH TTY，在 attach 注册后的约 2 秒内轮询 `list-clients` 找到对应 client。
- 对该 client 反复执行 `refresh-client -D 999`，把可见区域移到底部；不执行 `switch-client`，也不改变共享 window 尺寸。
- iOS 终端视图缩放时记录键盘前的完整 MUX 行数；键盘请求/已显示期间不把 SSH PTY 缩到键盘上方的可视高度，避免第二次裁剪把输入区从快照中移除。

## 验证方式

- `cd MobileApp/androidApp && ./gradlew :app:testDebugUnitTest --no-daemon`：通过。
- `./gradlew :app:assembleDebug --no-daemon`：通过，并已覆盖安装到 `emulator-5556`。
- `xcodebuild -project MobileApp/iosApp/Termirror.xcodeproj -scheme Termirror -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`：通过。
- iOS MUX 单元测试（4 项）通过；真实现场用例连接到了当前不可达的 `192.168.0.101` 配置，未完成 tab-15 截图验收。
- 需要在模拟器已有 `tab-15` 配置和真实 SSH/tmux 服务上重新进入会话，确认 `gpt-5.6-sol ...` 输入行与 tmux 页脚同时可见。

## 预防措施

- `ignore-size` 与手机客户端可见区域是两个独立问题；Android/iOS MUX attach 都必须在 client 注册后显式校正纵向 viewport。
