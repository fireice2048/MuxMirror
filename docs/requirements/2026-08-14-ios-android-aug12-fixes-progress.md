# iOS/Android 复用 8 月 12 日问题修复进度

- [x] 定位 8 月 12 日提交及对应 bugfix 记忆，确认 iOS/Android 仍使用旧逻辑。
- [x] 修复 Android MUX 导航去重、目录标题和 attach 命令。
- [x] 修复 iOS MUX 导航去重、目录标题和 attach 命令。
- [x] 增加两端回归测试并运行构建/测试。
- [x] 记录验证结果并提交最终变更。

## 验证记录

- Android `./gradlew :app:testDebugUnitTest --no-daemon`：5 项通过。
- iOS `xcodebuild ... test`：`TermirrorTests` 5 项通过；既有 `ServerListUITests.testMuxNavNavigation` 因模拟器未配置真实服务器失败，其余 UI 用例通过。
- `cargo test --workspace`：7 项通过。
- `MobileApp/shared` `cargo test`：81 项通过。
