# Android/iOS 全屏 TUI 远端回看实现进度

需求文档：[2026-08-14-android-ios-tui-remote-scrollback.md](2026-08-14-android-ios-tui-remote-scrollback.md)

- [x] 记录需求、交互方案和验收标准
- [x] Android 解析并传递 `mouseProtocol`
- [x] Android 实现双指远端滚轮和上下文 PGUP/PGDN
- [x] Android 补充单元测试并完成 Debug 构建
- [x] iOS 解析并传递 `mouseProtocol`
- [x] iOS 实现双指远端滚轮和上下文 PGUP/PGDN
- [x] iOS 补充测试并完成模拟器构建
- [x] 更新平台 README 和功能记忆

## 构建验收记录（2026-08-14）

- Android：四个 Rust ABI 均交叉编译成功；修复构建脚本尾部 `cbindgen` 对稳定版 Rust 的兼容问题。执行 `./gradlew :app:testDebugUnitTest :app:assembleDebug` 成功；滚轮编码与距离累计共 2 项单元测试通过，生成 Debug APK。
- iOS：执行 `MobileApp/shared/scripts/build-ios.sh`，完成 `aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios` 构建并重建 XCFramework。
- iOS：在 iPhone 17 Pro、iOS 26.5 模拟器执行 `-only-testing:TermirrorTests test`，2 项单元测试通过，应用完成构建和启动。
- 双指手势仍需在 Android/iOS 真机连接真实 TUI 后确认触控手感；本次自动验收覆盖协议、事件状态传递和平台构建。
