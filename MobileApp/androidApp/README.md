# Termirror Android App

采用 **Kotlin + Jetpack Compose** 复刻鸿蒙端 UI 与操作体验。

## 目录结构

```
androidApp/
├── app/
│   ├── build.gradle.kts          # 应用模块 + JNA + Compose + Rust .so 拷贝
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/termirror/mobile/android/
│       │   ├── MainActivity.kt            # 导航入口
│       │   ├── TermirrorApplication.kt    # 初始化 Rust 核心
│       │   ├── core/
│       │   │   ├── TermirrorCore.kt       # JNA 封装 Rust C ABI
│       │   │   └── Models.kt              # TmEvent / ServerConfig
│       │   └── ui/
│       │       ├── theme/
│       │       ├── components/
│       │       │   ├── TerminalDisplayContract.kt  # 显示后端契约
│       │       │   ├── TerminalToolbar.kt          # 双行 20 键工具条
│       │       │   ├── ServerEditDialog.kt
│       │       │   └── TerminalComposeView.kt      # 默认 Compose 终端渲染
│       │       └── pages/
│       │           ├── ServerListScreen.kt
│       │           ├── TerminalScreen.kt
│       │           ├── NetworkDiagScreen.kt
│       │           └── MuxNavScreen.kt
│       └── jniLibs/
└── build.gradle.kts / settings.gradle.kts
```

## 架构

- 复用 `MobileApp/shared/` Rust 核心 `termirror_core`。
- Android 通过 JNA 加载 `libtermirror_core.so`（无需手写 JNI shim）。
- UI 层只负责展示与交互，不实现终端逻辑。
- `TerminalDisplayController` 接口封装显示后端，当前默认实现为 `TerminalComposeView`（基于 Jetpack Compose Text + AnnotatedString），后续可替换为 Canvas 或第三方原生终端控件，无需改动页面层。
- 终端单指纵向滑动用于本地历史；远端全屏 TUI 开启鼠标跟踪后，双指纵向滑动发送 SGR/X10 滚轮。工具栏和外接键盘 `PGUP` / `PGDN` 会按当前鼠标模式执行远端按页回看或普通 Shell 本地翻页。
- 不引入 WebView 终端渲染。

## 构建

### 前置条件

- Android Studio 或 Android 命令行工具
- Android SDK + NDK（建议 NDK 26）
- Rust 已安装并添加 Android target：
  ```sh
  rustup target add aarch64-linux-android
  ```

### 构建 Rust 核心

```sh
cd MobileApp/shared
bash scripts/build-android.sh
# 产物：target/aarch64-linux-android/release/libtermirror_core.so
```

### 构建 Android APK

首次构建 Android 工程时，Gradle 会自动把 `.so` 从 `shared/target` 拷贝到 `app/src/main/jniLibs/arm64-v8a/`。

```sh
cd MobileApp/androidApp
# 建议用 Android Studio 打开并运行
# 或使用 Gradle wrapper（如果本机已生成 wrapper）
./gradlew :app:assembleDebug
```

## 已知限制

- 当前终端渲染为 Compose Text 方案，光标闪烁与宽字符 letterSpacing 等细节后续可继续打磨。
- 服务器列表拖动排序依赖 `org.burnoutcrew:compose-reorderable` 库；若版本不兼容请调整版本号或改用上下移动按钮。
- Android 版本当前提供完整骨架与主要页面；模拟器/真机网络权限、软键盘交互等需真机验收。
