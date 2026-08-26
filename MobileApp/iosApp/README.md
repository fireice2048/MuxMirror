# MuxMirror iOS App

采用 **SwiftUI + 原生 TextKit 终端渲染** 复刻鸿蒙端 UI 与操作体验。

## 目录结构

```
iosApp/
├── project.yml                 # XcodeGen 工程描述
├── Termirror/
│   ├── TermirrorApp.swift      # @main 入口 + NavigationStack
│   ├── Core/
│   │   └── TermirrorCore.swift # Rust C ABI 薄封装
│   └── UI/
│       ├── Components/
│       │   ├── TerminalDisplayContract.swift  # 显示后端契约
│       │   ├── TerminalToolbar.swift          # 双行 20 键工具条
│       │   └── TerminalTextView.swift         # 默认 Compose 式终端渲染
│       └── Pages/
│           ├── ServerListScreen.swift
│           ├── TerminalScreen.swift
│           ├── NetworkDiagScreen.swift
│           └── MuxNavScreen.swift
└── README.md
```

## 架构

- 复用 `MobileApp/shared/` Rust 核心 `termirror_core`。
- iOS 直接链接 `build/ios/TermirrorCore.xcframework`（C ABI）。
- UI 层只负责展示与交互，不实现终端逻辑。
- `TerminalDisplayController` 协议封装显示后端，当前默认实现为 `TerminalTextView`（基于 `UITextView` + `NSAttributedString`），后续可替换为 SwiftTerm 等第三方原生终端控件，无需改动页面层。
- 终端单指纵向滑动用于本地历史；远端全屏 TUI 开启鼠标跟踪后，双指纵向滑动发送 SGR/X10 滚轮。工具栏和外接键盘 `PGUP` / `PGDN` 会按当前鼠标模式执行远端按页回看或普通 Shell 本地翻页。
- 不引入 WebView 终端渲染。

## 构建

### 前置条件

- macOS + Xcode 16+
- Rust 已安装并添加 iOS target：
  ```sh
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```
- 安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（用于生成 `.xcodeproj`）：
  ```sh
  brew install xcodegen
  ```

### 构建 Rust 核心

```sh
cd MobileApp/shared
bash scripts/build-ios.sh
# 产物：build/ios/TermirrorCore.xcframework
```

### 生成并运行 iOS 工程

```sh
cd MobileApp/iosApp
xcodegen generate
# 打开生成的 Termirror.xcodeproj 并在 Xcode 中签名/运行
open Termirror.xcodeproj
```

或使用命令行构建到模拟器：

```sh
xcodebuild -project Termirror.xcodeproj -scheme Termirror -destination 'platform=iOS Simulator,name=iPhone 16' build
```

仅运行终端交互单元测试：

```sh
xcodebuild -project Termirror.xcodeproj -scheme Termirror \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TermirrorTests test
```

## 已知限制

- 当前终端渲染为原生 `UITextView` 方案，光标闪烁与宽字符对齐等细节后续可继续打磨。
- MUX 导航返回后自动 attach 目标由 `NavigationStack` 状态传递，完整实现需进一步接入 `savedState`/`ObservableObject`。
- iOS 版本当前仅提供工程骨架与主要页面；真机签名、ATS 配置等由 Xcode 工程自动处理。
