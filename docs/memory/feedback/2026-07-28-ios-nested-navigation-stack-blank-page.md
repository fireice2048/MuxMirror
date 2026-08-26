# iOS 嵌套 NavigationStack 导致 MUX 跳转后闪退/空白页

## 现象

- 触发条件：在 iOS 终端页点击顶部 `MUX...` 按钮，进入 MUX 导航页后再返回。
- 用户影响：
  - 屏幕闪烁后终端页消失，自动回到首页。
  - 回到首页后，点击服务器列表项或「网络诊断」按钮，页面进入空白页，无法继续操作。
  - 必须重启 App 才能恢复。

## 根因

- `ContentView` 已经使用一个根 `NavigationStack(path: $path)` 管理全页路由（首页 → 终端页 → MUX 导航页、网络诊断页）。
- `ServerListScreen` 和 `MuxNavScreen` 内部又各自包了一层 `NavigationStack`，形成嵌套导航栈。
- SwiftUI 的 `NavigationStack` 嵌套时，系统返回手势/按钮会作用在最内层栈，而 `path.append/removeLast` 操作的是外层栈，导致两个栈状态不一致。
- 当内层栈把页面 pop 空后，外层栈仍认为当前路由存在，后续再 `append` 新路由时渲染出空白视图。

## 修复方案

- 涉及模块：
  - `MobileApp/iosApp/Termirror/UI/Pages/ServerListScreen.swift`
  - `MobileApp/iosApp/Termirror/UI/Pages/MuxNavScreen.swift`
- 关键改动：
  - 移除 `ServerListScreen` 内部的 `NavigationStack`，将 `.onAppear`、`.sheet`、`.alert` 等修饰符直接挂到 `serverListContent` 上。
  - 移除 `MuxNavScreen` 内部的 `NavigationStack` 和自定义「关闭」按钮，仅保留 `.navigationTitle("导航")`。
  - 统一由 `ContentView` 的根 `NavigationStack` 负责页面导航和系统返回按钮。

## 验证方式

- 复现步骤：
  1. 启动 App 并新增一个服务器。
  2. 点击服务器进入终端页。
  3. 点击 `MUX...` 进入导航页。
  4. 返回终端页，再返回首页。
  5. 点击「网络诊断」，应正常进入网络诊断页。
- 验证命令：

  ```sh
  cd MobileApp/iosApp
  xcodegen generate
  xcodebuild -project Termirror.xcodeproj -scheme Termirror \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:TermirrorUITests test
  ```

- 验证结果：新增 `testMuxNavNavigation` UI 测试，包含上述完整流程；全部 5 个 UI 测试通过，无失败。

## 预防措施

- iOS 侧应始终坚持「单一根 NavigationStack」原则：只有 `ContentView`（或 App 级容器）持有 `NavigationStack`，业务页面只负责内容视图和 `.navigationTitle`/`.toolbar` 修饰符。
- 新增页面时，若出现返回按钮重复、跳转后空白、页面层级异常等现象，优先检查是否存在嵌套 `NavigationStack`。
- UI 测试覆盖跨页面导航的主路径，避免回归。
