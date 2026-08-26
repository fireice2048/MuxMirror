# TermMirror 移动端 iOS/Android 复刻需求

日期：2026-07-26
状态：已确认，开发中

## 背景

鸿蒙端 `MobileApp/harmonyApp/` 已完整实现 TermMirror 移动端全部功能：服务器列表管理、SSH 直连终端、MUX 导航、网络诊断、双行 20 键工具条、安全粘贴、日志与配置持久化。核心逻辑全部沉淀在 `MobileApp/shared/` Rust crate `termirror_core` 中，通过 C ABI 薄层导出。

现需将鸿蒙端的 UI 布局、功能与操作体验完整复刻到 iOS 与 Android 两个原生平台。

## 目标

- 在 `MobileApp/` 下新增：
  - `androidApp/`：Android 原生客户端（Kotlin + Jetpack Compose）。
  - `iosApp/`：iOS 原生客户端（SwiftUI）。
- 复用 `MobileApp/shared/` Rust 核心，不重复实现终端逻辑、SSH 会话、ANSI 处理、输入编码、配置与日志。
- 通过统一 C ABI `ffi/include/termirror_core.h` 与 Rust 核心交互：Android 走 JNI，iOS 直接 C 互操作。
- 终端渲染可以使用平台原生或第三方原生终端控件，**禁止使用 WebView 方案**。
- 保持鸿蒙端确立的「显示组件可切换」架构：Android/iOS 都要定义 TerminalDisplayContract（接口/协议），默认实现一个原生渲染后端，后续可无缝替换为其他原生终端控件而不影响上层页面。
- 三端操作体验一致：服务器列表 CRUD/排序、SSH 终端连接与输入、工具条、MUX 导航、网络诊断、失败/超时/重试状态。

## 平台需求

### Android

- 语言/框架：Kotlin + Jetpack Compose。
- 最低 API：Android 8.0（API 26），优先支持 arm64-v8a，按需支持 armeabi-v7a/x86_64。
- Rust 目标：`aarch64-linux-android`、`armv7-linux-androideabi`（可选）、`x86_64-linux-android`（模拟器）。
- 终端渲染：使用 Jetpack Compose 自定义 Text/Canvas 后端（对齐鸿蒙 TerminalNativeView），禁用 WebView。
- 权限：`INTERNET`。

### iOS

- 语言/框架：SwiftUI + UIKit 桥接。
- 最低版本：iOS 16.0。
- Rust 目标：`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`（模拟器）。
- 终端渲染：默认使用 SwiftTerm（纯 Swift/Cocoa 终端模拟器，非 WebView），通过 TerminalDisplayContract 协议封装，保留切换能力。
- 权限：网络（App Transport Security 按需允许明文或仅 TLS）。
- 输入焦点与终端渲染补充要求：
  - 服务器新增/编辑等普通输入框在 iPhone 17 Pro 模拟器点击后必须弹出
    系统软键盘，并保持可编辑状态。
  - 终端页点击终端区域或键盘工具按钮后必须弹出软键盘；关闭后仍可继续
    接收外接硬件键盘，不得因第一响应者切换而永久失焦。
  - 终端输出必须保留 Rust 核心提供的 ANSI 前景色、背景色、反色和暗色
    样式，不能统一覆盖成绿色。
  - 终端渲染必须以稳定的 UTF-16/字符范围应用样式，PTY 列宽与显示字体
    尺寸应一致，避免宽字符、光标或频繁快照更新导致错位、折行混乱。

## 关键流程（对齐鸿蒙版）

1. 启动：App 初始化 Rust 核心（`tm_init` + `tm_on_event`），应用文件目录传给核心做日志/配置根目录。
2. 服务器列表：
   - 展示 `tm_config_list` 返回的配置；支持新增/编辑/复制/删除。
   - 长按或拖动排序，调用 `tm_config_move` 持久化。
3. 终端页：
   - 点击服务器后调用 `tm_session_connect` 建立 SSH 会话，10 秒连接超时。
   - 接收 `output` / `connectionState` / `error` 事件更新画面。
   - 使用可切换终端显示组件渲染快照、光标、ANSI 样式。
   - 底部双行 20 键工具条：ESC/TAB/方向/Home/End/PgUp/PgDn/Del、常用符号、CTRL/ALT 锁定、粘贴、键盘开关。
   - 系统软键盘输入经 Rust `tm_encode_key` 编码后 `tm_session_write`。
   - 尺寸变化经 `tm_session_resize` 同步 PTY。
   - iOS 双行工具条按键文字必须保持单行显示，`HOME`、`PGUP`、`PGDN`
     等长标签不得折行；键盘开关使用与其他按键前景色一致的 SF Symbol。
   - iOS 终端页导航栏与状态栏使用系统动态背景和前景色，跟随浅色/深色
     主题，不得因终端内容为黑色而固定变黑。
   - iOS 终端显示区域采用电脑端 macOS Terminal `Clear Dark` 的默认前景色、
     背景色和 16 色 ANSI 调色板；应用输出的 24 位真彩色必须原样保留，不能
     把 `ESC[39m` 默认前景色统一渲染成品牌浅绿色。
   - iOS 与 Android 终端页必须接受模拟器电脑键盘及外接硬件键盘输入：
     普通字符、Enter、退格和方向键等特殊键均应沿现有输入链路发送给
     Rust 核心，不得仅支持屏幕软键盘。
4. MUX 导航：
   - 终端页标题栏「MUX...」入口。
   - 调用 `tm_session_exec` 执行 `muxmirror -format json --mux`。
   - 解析 JSON 展示窗口/标签页/detached 会话列表。
   - 每个导航项必须携带可唯一定位窗口/标签的目标标识；选中后进入终端页，
     `tmux/rmux attach-session` 必须附带对应窗口目标，不能只传所有窗口共有的
     session 名而总是落到当前活动窗口。
   - SSH 登录脚本可能已经自动进入默认 tmux/rmux 会话；此时选中导航项必须先
     使用 `switch-client` 切换现有 client，仅在普通 shell 中才回退到
     `attach-session`，不得因嵌套 attach 失败而停留在默认会话。
   - 至少使用两个不同窗口做真实联调，分别进入后应通过 tmux/rmux 状态栏或
     当前窗口信息证明目标不同；仅验证“能 attach”不算通过。
5. 网络诊断：
   - 黑底绿字输出区。
   - 解析 `tcp <IP/域名> [端口]` 并调用 `tm_tcp_check`。
   - 结果经 `diag` 事件回填。

## 非目标（本期不做）

- PCServer Attach TCP 协议对接（沿用 SSH 直连方案）。
- 公钥认证、主机密钥持久化、keyboard-interactive 认证（沿用鸿蒙当前能力）。
- 加密保存密码（沿用鸿蒙当前明文 YAML 方案）。
- 平台商店发布相关配置（签名、隐私清单、应用内购买等）仅做基础工程级配置。
- 与已删除目录 `MobileClient/` 产生任何依赖或引用。

## 待澄清问题

- Android 模拟器/真机是否需要预编译 libssh2/mbedtls 静态库，还是复用 `MobileApp/shared/third_party/` 的源码脚本重新为 Android target 构建。
- iOS 的 SwiftTerm 通过 Swift Package Manager 还是 CocoaPods 引入，是否允许作为可选外部依赖。
- 是否需要在 Android 上额外实现本地终端（Local shell）功能；鸿蒙版以网络诊断页替代蓝本的本地终端页。

## 架构约束

- Rust Core 不感知任何平台 UI 概念，只输出事件与数据模型。
- 各端 UI 只负责展示与交互，禁止在 UI 层实现 ANSI 解析、屏幕缓冲、会话状态机。
- FFI 薄层只转发和编解码，不承载业务逻辑；接口变更需向后兼容。
- 服务器地址等环境配置写入文件，禁止 hardcode 到代码中。
