# Mobile 客户端里程碑进度

本文用于跟踪 Attach Mobile 客户端阶段性进展。每完成关键里程碑，应同步更新本文。

## 已完成里程碑

### 1. 跨平台移动端骨架

- 已建立 Android、iOS、HarmonyOS 与 Compose Multiplatform 共享 UI 的基础工程结构。
- 已接入 HarmonyOS ArkUI 容器，通过 Native/Compose 桥接加载共享 UI。
- 已保留各平台入口职责边界，业务 UI 主要集中在共享 Compose 层。

### 2. 移动端首页与终端占位流程

- 已完成移动端首页服务器列表、服务器编辑弹窗、终端页占位流程。
- 已支持从服务器列表进入终端页，并提供返回列表的基础导航。
- 已支持终端输入框和换行按钮，为后续真实远程终端交互预留 UI 流程。

### 3. 移动端品牌化

- 已将移动端 App 显示名统一为 `ATTACH`。
- 已替换 Android、iOS、HarmonyOS 的 App 图标资源。
- 已替换首页顶部品牌 Banner，并修复 HarmonyOS Compose rawfile 资源路径问题。

### 4. 服务器列表本地持久化

- 已实现服务器配置列表的共享编码/解码能力，并添加单元测试覆盖。
- 已实现 Android、iOS、HarmonyOS 三端本地存储适配。
- 已修复 HarmonyOS 侧应用沙箱路径问题，使用真实 `filesDir` 保存服务器配置。
- 已确认 App 普通重启后新增/复制的服务器配置可以保留；卸载重装会清除沙箱数据。

### 5. HarmonyOS 真机验证链路

- 已建立 HarmonyOS 编译发布流程：先发布 Compose 共享库，再构建 HarmonyOS App。
- 已在 `HUAWEI Pura 70` 真机上完成多轮安装、启动和崩溃日志验证。
- 已明确日常验证命令：不需要清数据时避免使用 `--uninstall`。

## 三端编译/运行验证（2026-07-08）

- [x] **HarmonyOS**：真机已验证（键盘避让、终端页布局）。本轮新增 OFFSET 避让方案待真机复验闪烁。
- [x] **iOS**：`xcodebuild` 在 iPhone 17 模拟器（iOS 26.3）编译并运行成功，PID 启动正常，无崩溃日志，Compose 正常渲染。修复了 iosApp 工程缺失 `PRODUCT_NAME`/`PRODUCT_BUNDLE_IDENTIFIER` 导致 `.app` 路径为空、以及缺失 `Preview Content` 目录导致 previews 失败的问题。
- [x] **Android**：本机无 emulator 二进制且无真机，仅完成 `./gradlew :androidApp:assembleDebug` 编译验证（APK 构建成功）。运行验证需开发者本地真机或安装 Android emulator 后补做。注：曾因脏 build 缓存引用残留 `Mobile/composeUI` 路径导致 `mergeLibDexDebug` 失败，清理 `composeUI/build`、`androidApp/build`、`.gradle` 后通过。
- [x] **Android 运行验证（补做，2026-07-09）**：本机安装 cmdline-tools、emulator、系统镜像（`android-36 google_apis_playstore arm64-v8a`，因 `android-36.1` 镜像在 Apple Silicon 上启动卡死，改用 android-36 镜像成功），创建 AVD `AttachTest36b` 并启动模拟器（`pixel_6`）；`adb install` 安装 `androidApp-debug.apk` 成功；`uiautomator dump` 确认终端页元素齐全：服务器列表、终端显示框、特殊键工具栏（ESC/TAB/CTRL/ALT/←/→/_/-/+/ /*）、3 行输入框「输入提示词」、换行按钮「↵」。Android 端三端验证闭环完成。

## 当前待推进里程碑

### 1. 真实连接能力

- 将服务器列表中的配置接入真实 SSH 或 Attach PC 服务端连接流程。
- 实现连接状态、错误提示和认证失败处理。

### 2. 终端会话交互

- 将终端页从占位内容升级为真实屏幕输出。
- 支持输入转发、换行、快捷键和移动端软键盘交互。

### 3. 移动端验收闭环

- 补充移动端手工验收文档，覆盖三端启动、列表持久化、连接流程和终端输入。
- HarmonyOS 真机、iOS 模拟器已验证；Android 需真机/模拟器补运行验证。

## 本轮迭代（2026-07-08）终端页交互优化

目标：修复移动端（HarmonyOS 优先）终端页交互问题，并补齐未尽事项。

- [x] 回车/换行按钮缩小至 40dp，图标居中
- [x] 输入框固定于屏幕底部，初始不滚动，点击输入框弹出软键盘时整体上移
- [x] 输入框加高至 3 行
- [x] 终端显示框撑满中间空白区域，且可滚动
- [x] 特殊按键工具栏（ESC/TAB/CTRL/ALT/←↓→/_-+/*）全部可点击
- [x] 符号键点击插入字符到输入框光标处
- [x] 特殊控制键点击发送 ANSI/控制序列（当前为占位反馈，未接真实 PTY）
- [x] 工具栏间距减小 75% 并支持横向滚动避免显示不全
- [x] 鸿蒙端键盘避让采用 RESIZE 模式 + 窗口全屏沉浸式，消除状态栏跳动（进行中验证）
- [ ] 真实 PTY / 终端绑定（未接，当前终端输出为占位文本）
- [ ] 控制序列真正通过 SSH/PTY 写出
- [ ] 输入框真正将文本发送至远程终端
- [ ] 三端真机/模拟器验收闭环
