# TermMirror — MobileApp 目录开发规则

## 产品信息

- **产品名称**: TermMirror
- **客户端目录**: 本目录（`MobileApp/`）
- **目标平台**: Android / iOS / HarmonyOS（鸿蒙）

## 目录结构

```
MobileApp/
├── shared/       # Rust 共享核心（三端复用），crate 名 termirror_core
├── harmonyApp/   # HarmonyOS 客户端（ArkTS）
├── androidApp/   # Android 客户端（Kotlin + Jetpack Compose）
└── iosApp/       # iOS 客户端（SwiftUI）
```

## 总体架构

```
Rust 终端核心（core）
    ↑↓ 薄 FFI 层（只传稳定事件和数据模型）
三端原生 UI
├── Android   → Kotlin
├── iOS       → SwiftUI
└── HarmonyOS → ArkTS
```

架构原则：**一份 Rust 核心 + 三端原生 UI + 薄 FFI 层**。

## 职责划分

### Rust Core（终端核心）

负责所有终端逻辑与状态，三端共享同一份实现：

- SSH 会话管理（连接、认证、断开、重连）
- 终端状态机
- 字节流处理
- ANSI / xterm 解析
- 屏幕缓冲（screen buffer）
- 输入序列编码（键盘输入 → 终端字节序列）
- 命令历史
- 协议编解码
- 并发任务管理
- 配置模型
- 日志

### 三端原生 UI（各自平台的原生 UI 库）

只做展示与交互，不实现终端逻辑：

- **Android**: Kotlin
- **iOS**: SwiftUI
- **HarmonyOS**: ArkTS

各端负责：

- 终端控件渲染（根据 Rust 输出的屏幕缓冲/diff 绘制）
- 键盘处理（虚拟键盘、特殊键、组合键）
- 粘贴
- 安全与权限
- 手势
- 无障碍（Accessibility）
- 页面导航

### FFI 层（薄层）

- **只传递稳定的事件和数据模型**，例如：
  - `write(bytes)` — 输入字节写入会话
  - `resize(cols, rows)` — 终端尺寸变更
  - `screen_diff` — 屏幕变化增量输出
  - `connection_state` — 连接状态变更事件
- **禁止 UI 直接操纵 Rust 内部对象**（不暴露内部指针、状态机、缓冲区结构）
- FFI 接口变更必须保证向后兼容，新增能力以新增接口方式扩展，不改动已有签名

## 开发规则

1. **逻辑归属判断**：新增功能先判断属于哪一层。凡是终端行为、协议、状态相关的逻辑，一律放 Rust Core；凡是展示、交互、平台能力相关的，放对应平台 UI 层。拿不准时先讨论再动手。
2. **禁止逻辑下沉到 UI 层**：不得在 Kotlin/Swift/ArkTS 中重复实现 ANSI 解析、屏幕缓冲、会话状态等核心逻辑。
3. **禁止逻辑上浮到 Core**：Rust Core 不感知任何平台 UI 概念（View、组件、生命周期等），只输出数据模型和事件。
4. **FFI 薄层原则**：FFI 不做业务逻辑，只做编解码与转发；接口粒度以事件/数据模型为单位。
5. **配置与地址**：服务端地址等环境相关配置写入配置文件（YAML 格式），不得 hardcode 到代码中。
6. **语言与文档**：代码注释、commit log、文档默认使用中文；commit log 必须用中文。
7. **修改前先说明**：动手修改前先说明将读取的文件和修改范围，优先最小可行改动，不引入不必要的新依赖。

## 当前状态与构建命令（2026-07-27）

- 开发路线：`MobileApp/`（Rust 核心 + 三端原生 UI）为现行方案；`MobileClient/`（KMP）已删除，不再开发，禁止引用该目录。SSH 依赖（libssh2/mbedTLS）自包含于 `MobileApp/shared/` 内部。
- 三端需求：`docs/requirements/2026-07-26-termirror-ios-android-replica.md`。
- 三端进度：`docs/requirements/termirror-ios-android-replica-progress.md`。
- Rust 核心构建：
  - 鸿蒙（aarch64 + x86_64 双 ABI `libtermirror_core.so`）：
    ```sh
    cd MobileApp/shared && bash scripts/build-ohos.sh
    ```
  - Android（目前脚本默认构建 aarch64 / armv7 / x86 / x86_64，按需裁剪）：
    ```sh
    cd MobileApp/shared && bash scripts/build-android.sh
    ```
  - iOS（真机 + 模拟器 XCFramework）：
    ```sh
    cd MobileApp/shared && bash scripts/build-ios.sh
    ```
- 鸿蒙工程构建：Rust .so 拷贝到 `MobileApp/harmonyApp/entry/libs/{arm64-v8a,x86_64}/` 后：
  ```sh
  cd MobileApp/harmonyApp && devecocli build
  ```
- Android 工程构建：先构建 Rust 核心，然后：
  ```sh
  cd MobileApp/androidApp && ./gradlew :app:assembleDebug
  ```
- iOS 工程构建：先构建 Rust 核心生成 `build/ios/TermirrorCore.xcframework`，再用 XcodeGen 生成 Xcode 工程：
  ```sh
  cd MobileApp/iosApp && xcodegen generate && xcodebuild -project Termirror.xcodeproj -scheme Termirror build
  ```
- ohos target 的 `target_os` 是 `"linux"`，平台 cfg 一律用 `#[cfg(target_env = "ohos")]`。

### 快捷脚本

- **`scripts/deploy-mobile.sh`**：一键完成 Rust 核心构建、原生应用编译、模拟器安装并启动。支持 iOS、Android 或同时部署两端。

  ```sh
  ./scripts/deploy-mobile.sh ios      # iOS（iPhone 17 Pro 模拟器）
  ./scripts/deploy-mobile.sh android  # Android（自动启动模拟器）
  ./scripts/deploy-mobile.sh all      # iOS + Android
  ```

  脚本特性：
  - Rust 核心已存在时自动跳过重复构建
  - Android 无连接模拟器时自动启动第一个 AVD
  - iOS 模拟器使用 iPhone 17 Pro
