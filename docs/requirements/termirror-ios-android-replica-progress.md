# TermMirror iOS/Android 复刻进度

起始日期：2026-07-26
需求文档：[2026-07-26-termirror-ios-android-replica.md](2026-07-26-termirror-ios-android-replica.md)

## 里程碑清单

### M1 文档与构建基础
- [x] 记录需求文档与进度文档（本文件）
- [x] 扩展 `MobileApp/shared/Cargo.toml` 与构建脚本，支持 Android/iOS target 编译
- [x] 生成/验证 `ffi/include/termirror_core.h` 在 Android/iOS 可用
- [x] iOS 真机/模拟器 Rust 核心构建成功，产出 `TermirrorCore.xcframework`
- [x] Android arm64 Rust 核心构建成功，产出 `libtermirror_core.so`
- [x] 记录 iOS Rust 交叉编译 `__chkstk_darwin` 踩坑到 `docs/memory/feedback/`
- [ ] Android 全 ABI 与 iOS 真机构建完整验证

### M2 Android 项目骨架
- [x] 创建 `MobileApp/androidApp/` Gradle 工程（Kotlin + Jetpack Compose）
- [x] 通过 JNA 加载 `libtermirror_core.so`
- [x] 实现 Rust 事件回调 JNA 桥（Java/Kotlin ↔ C ABI）
- [x] 实现应用初始化与配置/日志目录准备

### M3 Android UI 复刻
- [x] 数据模型与事件总线（对齐鸿蒙 `TermirrorCore.ets`）
- [x] 服务器列表页 + 新增/编辑/删除弹窗
- [x] 服务器列表拖动排序
- [x] 网络诊断页
- [x] MUX 导航页（含 JSON 解析与标签页菜单占位）
- [x] 终端页编排层（连接生命周期、标题栏、工具条、粘贴、键盘）
- [x] 终端显示组件契约（`TerminalDisplayContract`）与默认 Compose 后端
- [x] 双行 20 键工具条组件
- [x] 修复浅色主题系统状态栏图标与白色背景同色不可见
- [x] 验收 Android 主屏/备用屏 ANSI 颜色及 MUX 会话标签可识别性
- [ ] Android 单元/UI 基础测试

### M4 iOS 项目骨架
- [x] 创建 `MobileApp/iosApp/` 工程目录（SwiftUI）
- [x] 通过 `TermirrorCore.xcframework` 直接 C 互操作链接 Rust 核心
- [x] 实现 C ABI 桥接封装（Swift 层 `TermirrorCore`）
- [x] 应用初始化与配置/日志目录准备
- [x] 提供 XcodeGen `project.yml` 生成 Xcode 工程
- [x] iOS 模拟器 `xcodebuild` 编译成功

### M5 iOS UI 复刻
- [x] 数据模型与事件总线
- [x] 服务器列表页 + 新增/编辑/删除
- [x] 服务器列表排序
- [x] 网络诊断页
- [x] MUX 导航页
- [x] 终端页编排层
- [x] 终端显示组件契约（`TerminalDisplay` 协议）与原生 TextKit 后端
- [x] 双行 20 键工具条组件
- [x] 修复 iOS 工具条文字折行、键盘图标配色和导航栏主题跟随（iPhone 17 Pro 模拟器截图验收）
- [x] 修复 iOS/Android 模拟器电脑键盘与外接硬件键盘输入（双端构建通过，Android 执行命令回归通过）
- [x] 复现 iOS 普通输入框与终端页软键盘无法弹出
- [x] 修复 iOS 第一响应者与软/硬键盘切换
- [x] 修复 iOS ANSI 多色渲染与终端排版稳定性
- [x] 完成 iPhone 17 Pro 模拟器截图和输入回归验收
- [x] 复现并修复 iOS MUX 导航不同窗口均进入默认 tmux 会话
- [x] 在真实导航页分别点击 `tab-8`、`tab-12` 并截图证明目标不同
- [x] 对齐 iOS `tab-8` 与电脑端 Clear Dark 默认色及 ANSI 16 色
- [ ] iOS 基础测试

### M6 集成与验收
- [x] 更新 `README.md` 与 `MobileApp/AGENTS.md` 说明新平台结构
- [x] 编写 Android 构建/运行命令说明
- [x] 编写 iOS 构建/运行命令说明
- [ ] 记录 Android 真机/模拟器验收结果与已知限制
- [ ] 记录 iOS 真机验收结果与已知限制

### M2 Android 项目骨架
- [x] 创建 `MobileApp/androidApp/` Gradle 工程（Kotlin + Jetpack Compose）
- [x] 通过 JNA 加载 `libtermirror_core.so`
- [x] 实现 Rust 事件回调 JNA 桥（Java/Kotlin ↔ C ABI）
- [x] 实现应用初始化与配置/日志目录准备

### M3 Android UI 复刻
- [x] 数据模型与事件总线（对齐鸿蒙 `TermirrorCore.ets`）
- [x] 服务器列表页 + 新增/编辑/删除弹窗
- [x] 服务器列表拖动排序
- [x] 网络诊断页
- [x] MUX 导航页（含 JSON 解析与标签页菜单占位）
- [x] 终端页编排层（连接生命周期、标题栏、工具条、粘贴、键盘）
- [x] 终端显示组件契约（`TerminalDisplayContract`）与默认 Compose 后端
- [x] 双行 20 键工具条组件
- [ ] Android 单元/UI 基础测试

### M4 iOS 项目骨架
- [x] 创建 `MobileApp/iosApp/` 工程目录（SwiftUI）
- [x] 通过 `TermirrorCore.xcframework` 直接 C 互操作链接 Rust 核心
- [x] 实现 C ABI 桥接封装（Swift 层 `TermirrorCore`）
- [x] 应用初始化与配置/日志目录准备
- [x] 提供 XcodeGen `project.yml` 生成 Xcode 工程

### M5 iOS UI 复刻
- [x] 数据模型与事件总线
- [x] 服务器列表页 + 新增/编辑/删除
- [x] 服务器列表排序
- [x] 网络诊断页
- [x] MUX 导航页
- [x] 终端页编排层
- [x] 终端显示组件契约（`TerminalDisplay` 协议）与原生 TextKit 后端
- [x] 双行 20 键工具条组件
- [ ] iOS 基础测试

### M6 集成与验收
- [ ] 更新 `README.md` 与 `MobileApp/AGENTS.md` 说明新平台结构
- [ ] 编写 Android 构建/运行命令说明
- [ ] 编写 iOS 构建/运行命令说明
- [ ] 记录验收结果与已知限制
