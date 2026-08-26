# TermMirror MobileApp（鸿蒙先行）需求文档

日期：2026-07-20
状态：已确认，开发中

## 背景

移动端此前采用 KMP 方案（`MobileClient/`，Compose Multiplatform + Kotlin/Native）。经评估后决定转向 **TermMirror 方案**：一份 Rust 终端核心 + 三端原生 UI + 薄 FFI 层（统一 C ABI）。KMP 方案停止开发，代码保留不删除。鸿蒙端先行，Android/iOS 后续补。

## 目标

- 在 `MobileApp/` 下从零搭建：
  - `shared/`：Rust 核心，crate 名 `termirror_core`，承载全部终端逻辑（SSH 会话、终端状态、ANSI 处理、输入编码、命令历史、配置、日志）。
  - `harmonyApp/`：纯 ArkTS 鸿蒙客户端，复刻 `MobileClient` 现有鸿蒙版的全部 UI 布局与交互。
- FFI 采用统一 C ABI（cbindgen 生成头文件），只传稳定事件与数据模型；Rust→UI 方向用单回调 + 事件枚举（`on_event(Event)`）。

## 平台需求

- 首期平台：HarmonyOS（API ≥ 20 模拟器/真机）。
- Rust 目标：`aarch64-unknown-linux-ohos`（后续按需加 x86_64 模拟器目标）。
- SSH 实现：首选 `ssh2` crate（libssh2），复用 `MobileClient/harmonyApp/scripts/build-ssh-dependencies.sh` 的 OHOS 交叉编译产物；受阻时回退纯 Rust `russh`。
- 服务器地址等配置写入 YAML 配置文件，禁止 hardcode。

## 关键流程（功能对齐现有鸿蒙版）

1. 服务器列表：展示/新增/编辑/复制/删除服务器配置（名称/地址/端口/用户/密码），YAML 持久化。
   - 支持长按服务器列表项后上下拖动排序；拖动中选中项以浮起效果跟手，其他列表项自动让位。
   - 松手后立即保存新顺序，App 重启后保持。
   - 列表项右侧编辑、复制、删除按钮保持现有图标大小，水平占用宽度由每项 46vp 缩减为 40vp。
   - 复制按钮复用原有彩色剪贴板 Emoji 两次并错位叠加，在直接表达“复制”的同时保持列表操作区的统一视觉风格。
2. SSH 终端：连接（密码 + 键盘交互认证回退，10 秒超时）→ 黑底绿字终端输出（ANSI 剥离 + `\r` 覆盖语义）→ 软键盘/硬件键盘输入 → 两行 20 键工具条（ESC/TAB/CTRL/ALT/方向键等）→ 安全粘贴（PasteButton）。
3. 网络诊断页：`tcp <IPv4> [端口]` 连通性检测。
4. 日志：启动 Banner、按天滚动保留 30 天、异步写线程、2 秒合并落盘（遵循全局日志规范）。

## 非目标（本期不做）

- Android / iOS 客户端。
- 完整终端屏幕缓冲与 screen_diff 增量协议（后续里程碑）。
- PCServer attach 协议（TCP/JSON）对接。
- 删除 MobileClient 目录。

## 待澄清问题

- 模拟器（x86_64）是否需要同步出 Rust ohos x86_64 产物以支持模拟器联调——M0 验证后确定。（注：现有 KMP 工程同时出 arm64-v8a/x86_64 两种 libkn.so）
- 完整 vt100 屏幕缓冲的引入时点与库选型（自研 vs vt100 crate）。
