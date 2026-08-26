# Mobile 跨平台客户端架构需求

## 背景

Attach Mobile 需要成为远程控制电脑端终端会话的跨平台移动客户端。用户要求使用 KMP + Compose Multiplatform，并参考 CPF-KMP-CMP 社区 Beta 版本，让 Android、iOS、HarmonyOS 三端复用同一套 UI 代码。

## 目标

- 使用 KMP + Compose Multiplatform 构建跨平台移动客户端。
- 三端共用 `composeUI` 中的一套 Compose UI 代码。
- 远程控制业务、协议模型和状态逻辑放入 `remote-control-shared` 公共模块。
- 平台入口拆分为 `androidApp`、`iosApp`、`harmonyApp`。
- App 入口模块只负责平台启动、权限、平台能力桥接和挂载共享 UI，不承载业务逻辑。
- 优先编译调试 HarmonyOS 客户端，同时保持 Android/iOS 可随时编译。

## 模块职责

### remote-control-shared

- 保存服务器配置、终端会话、Attach 协议请求/响应等公共模型。
- 保存输入编辑、快捷键、远程控制状态机等纯业务逻辑。
- 不依赖 Compose、不依赖平台 UI。

### composeUI

- 保存共享 Compose UI，包括服务器列表页、终端会话页、快捷键栏和输入提示词栏。
- 依赖 `remote-control-shared`。
- 输出 Android 可依赖的 UI 库、iOS Framework、HarmonyOS Native shared library。

### androidApp

- Android 应用入口。
- 只负责 Activity、Manifest、权限和平台桥接。
- 通过 `setContent` 挂载 `AttachApp()`。

### iosApp

- iOS 应用入口。
- 只负责 SwiftUI / UIKit 入口和平台桥接。
- 通过共享 Framework 挂载 `MainViewController()`。

### harmonyApp

- HarmonyOS 应用入口。
- 只负责 ArkTS EntryAbility、EntryAbility UI 页面、NAPI/native 桥接和平台能力。
- 通过 CPF-KMP-CMP 产物加载 `composeUI` 共享 Compose UI。

## 关键流程

1. 首页只展示服务器列表，不混入终端预览。
2. 用户可以新增、编辑、复制、删除服务器配置。
3. 点击服务器后模拟连接成功并进入终端页。
4. 终端页展示工作区、快捷键栏、输入框和独立 `↵` 换行按钮。
5. Gradle 构建 `remote-control-shared` 公共逻辑。
6. Gradle 构建 `composeUI` 共享 UI。
7. Android 入口依赖 `composeUI` 并编译 APK。
8. iOS 入口链接 `composeUI` 产物并编译 iOS App。
9. HarmonyOS 先运行 `:composeUI:publishDebugBinariesToHarmonyApp` 复制 `libkn.so`、头文件和资源。
10. 使用 DevEco/Hvigor 构建 `harmonyApp`，真机运行依赖本机 DevEco 自动签名生成的 `signingConfigs`。

## 非目标

- 第一阶段不实现真实 SSH 登录。
- 第一阶段不实现完整 Attach TCP 协议客户端。
- 第一阶段不在平台 app 入口中写业务逻辑。
- 第一阶段不引入平台专属 UI 分叉。
- 不提交 HarmonyOS 本机签名证书、profile 或密码。

## 待澄清问题

- CPF-KMP-CMP Beta 版本的依赖仓库和二进制产物是否需要内网缓存或私有镜像。
- HarmonyOS 签名和真机调试配置是否由 DevEco Studio 自动签名完成。
- 后续 SSH 能力应优先使用 KMP 公共库、平台原生桥接，还是远端命令代理。
