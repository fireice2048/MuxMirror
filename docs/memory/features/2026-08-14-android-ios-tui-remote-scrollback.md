# 功能记忆：Android/iOS 全屏 TUI 远端回看

## 背景

- 鸿蒙端完成全屏 TUI 远端回看后，Android 与 iOS 仍只能滚动客户端本地文本快照。
- 目标应用不限于 Codex，也包括 OpenCode、Claude Code、Kimi Code 等主动启用终端鼠标跟踪的 TUI。

## 关键功能点

- Rust 核心的 C ABI 事件 JSON 已自动携带 `mouseProtocol`，Android/iOS 只需解析并传入显示组件，不需要新增 FFI 函数。
- Android Compose 和 iOS TextKit 均保留单指本地滚动，将双指纵向手势独立映射为远端滚轮。
- 工具栏及外接键盘 `PGUP` / `PGDN` 复用上下文翻页：鼠标跟踪开启时发送 8 个远端滚轮刻度，否则滚动一个本地可视页。
- 两端均支持 SGR 与 X10 编码；手势每累计 28 像素发送一个刻度，每次更新最多 4 个。

## 设计与实现

- Android 在 `TerminalDisplayContract.kt` 中提供纯 Kotlin 编码与距离累计函数；`TerminalComposeView` 在 Pointer Initial pass 观察双指并消费双指事件，避免现有 `verticalScroll` 抢占，同时不影响单指。
- iOS 将 `UITextView.panGestureRecognizer.maximumNumberOfTouches` 设为 1，并增加限定两指的 `UIPanGestureRecognizer`；两个识别器允许并行，职责按手指数分离。
- 两端都只判断 Rust 解析出的 DEC 鼠标模式，不维护应用名称白名单。普通 Shell 的 `mouseProtocol` 为 `none`，因此不会收到不可见的鼠标转义序列。

## 验证方式

- Android：`./gradlew :app:testDebugUnitTest :app:assembleDebug`，构建成功，2 项滚轮契约单元测试通过。
- iOS：先执行 `MobileApp/shared/scripts/build-ios.sh` 重建真机与模拟器 XCFramework，再用 iPhone 17 Pro（iOS 26.5）模拟器执行 `xcodebuild ... -only-testing:TermirrorTests test`，2 项测试通过，应用目标随测试成功构建并启动。
- Android 首次执行四 ABI 构建后，旧脚本末尾的 `cbindgen` 因稳定版 Rust 拒绝 `-Zunpretty` 而失败；已与 iOS 脚本对齐，用 `RUSTC_BOOTSTRAP=1` 生成头文件，并将头文件刷新失败降级为不影响已完成 ABI 产物的警告。

## 后续注意事项

- Android Compose 的双指检测需要在 `PointerEventPass.Initial` 执行；若改到 Main/Final pass，`verticalScroll` 可能先消费事件。
- iOS 若替换 `UITextView`，必须继续明确区分单指本地滚动和双指远端滚轮，不能让两个 Pan 同时改变本地偏移。
- tmux/rmux 是否透传 pane 内应用的鼠标模式仍取决于远端配置；排查时先确认电脑端同会话鼠标滚轮可用。
