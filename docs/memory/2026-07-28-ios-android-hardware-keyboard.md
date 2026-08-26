# BugFix 记忆：iOS/Android 终端不接受硬件键盘输入

## 现象

- 触发条件：进入 iOS 或 Android 终端页后，直接使用模拟器电脑键盘或外接
  硬件键盘输入。
- 用户影响：屏幕软键盘和工具条可用，但普通字符及 Enter、退格、方向键等
  硬件按键无法稳定发送到 SSH 会话。
- 同期 iOS 视觉问题：工具条 `HOME` 折行、键盘字符图标呈灰色，终端页
  导航栏和状态栏固定变黑。

## 根因

- iOS 只有 1pt 隐藏 `UITextField` 在点击键盘按钮后才成为第一响应者，终端
  控制器本身不接收硬件 `UIPress`，方向键等也没有映射。
- Android 只有隐藏 `BasicTextField` 处理软键盘文本，未建立默认硬件焦点；
  `onPreviewKeyEvent` 仅处理 Enter。
- iOS 工具条使用 13pt 字号且没有单行限制，键盘字符 `⌨` 不服从模板前景色；
  导航栏只声明可见，没有显式使用系统动态背景和主题。

## 修复方案

- 涉及模块：
  - `MobileApp/iosApp/Termirror/UI/Components/TerminalTextView.swift`
  - `MobileApp/iosApp/Termirror/UI/Components/TerminalToolbar.swift`
  - `MobileApp/iosApp/Termirror/UI/Pages/TerminalScreen.swift`
  - `MobileApp/androidApp/app/src/main/java/com/termirror/mobile/android/ui/components/TerminalComposeView.kt`
- iOS 控制器默认成为第一响应者且不弹软键盘，通过 `pressesBegan` 转发普通
  字符、控制组合键和常用命名键；屏幕键盘关闭后恢复硬件焦点。
- Android 增加独立硬件焦点层，默认请求焦点；点击终端或键盘按钮仍切换到
  原有 IME 输入框。硬件字符和命名键统一调用 `tm_encode_key`。
- iOS 工具条字号调整为 11pt 并限制单行，键盘按钮改用单色 SF Symbol；
  导航栏使用 `systemBackground` 和当前 `colorScheme`。

## 验证方式

- 验证命令：
  - `xcodebuild -project Termirror.xcodeproj -scheme Termirror -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - `./gradlew :app:assembleDebug`
  - Android 模拟器：`adb shell input text 'echo%stermirror_android_hw'` 后发送
    `KEYCODE_ENTER`。
- 验证结果：
  - iOS 与 Android Debug 构建成功。
  - iPhone 17 Pro 模拟器确认 `HOME` 单行、键盘图标同色、浅色导航栏与状态栏
    正常。
  - Android 模拟器终端显示命令及回显 `termirror_android_hw`，证明无需打开
    软键盘即可输入。

## 预防措施

- 终端输入组件必须分别维护 IME 焦点与硬件键盘焦点，关闭屏幕键盘不等于
  放弃硬件输入。
- 新增按键时同步检查 iOS `UIKeyboardHIDUsage`、Android `KEYCODE_*` 与
  Rust `tm_encode_key` 的名称映射。
- 十等分工具条的长标签必须设置单行和缩放策略，图标优先使用平台模板图标。
