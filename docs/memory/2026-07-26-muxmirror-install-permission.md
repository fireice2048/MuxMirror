# 功能记忆：muxmirror 安装期辅助功能权限引导

## 背景

- 需求来源：旧版 muxmirror 首次枚举窗口时在 `/tmp` 动态编译 AX Helper，导致手机首次连接后才在电脑端出现权限提醒。
- 使用场景：用户在电脑本机安装服务端时完成 macOS 辅助功能授权，之后手机端只消费已经就绪的窗口枚举能力。

## 关键功能点

- AX Helper 使用独立 Swift 源码，并安装到稳定用户目录。
- `muxmirror setup` 显式申请权限、打开辅助功能设置并输出中文指引。
- `muxmirror doctor` 只检查 Helper 与权限状态，不触发权限弹窗。
- 正常窗口枚举不再动态编译，也不会主动弹出权限请求。
- Helper 缺失、权限缺失和执行失败均返回非零状态及明确诊断。

## 设计与实现

- 涉及模块：`MirrorServer/src/main.rs`、`MirrorServer/macos/MuxMirrorAXHelper.swift`、`scripts/install-muxmirror.sh`。
- 核心流程：安装脚本构建 Rust 主程序，预编译 Swift Helper，部署到稳定路径，再由 Helper 自身调用 `AXIsProcessTrustedWithOptions` 请求权限。
- 权限主体：macOS 会把 SSH 启动的 CLI 辅助功能访问归属到
  `sshd-keygen-wrapper`。本机终端直接运行 Helper 只能验证终端自身权限，
  因此 `setup`、`doctor` 和普通窗口扫描在非 SSH 环境下都通过 localhost
  SSH 执行 Helper；在已有 SSH 环境中直接执行。这样本机与手机端不会出现
  一边提示无权限、另一边却能枚举窗口的结果分裂。
- localhost SSH 禁用公钥尝试并优先使用密码认证，避免 SSH Agent 加载过多
  密钥时在密码提示前触发 `Too many authentication failures`。执行命令
  必须继承终端输入，不能使用关闭 stdin 的 `.output()` 包装伪终端。
- 重要约束：macOS TCC 权限不能由安装脚本静默授予；必须由用户在系统设置中确认。清理旧状态时只处理 muxmirror 相关条目，禁止全局重置 Accessibility。

## 验证方式

- 命令：
  - `cargo test --manifest-path MirrorServer/Cargo.toml`
  - `swiftc -O -framework Cocoa -framework ApplicationServices MirrorServer/macos/MuxMirrorAXHelper.swift -o <临时路径>`
  - `MUXMIRROR_INSTALL_ROOT=<临时目录> MUXMIRROR_SKIP_PERMISSION_PROMPT=1 scripts/install-muxmirror.sh`
  - `MUXMIRROR_PERMISSION_CONTEXT=direct MUXMIRROR_AX_HELPER=<临时Helper> <临时muxmirror> doctor`
- 结果：Rust 测试、Swift 编译、临时前缀安装均通过；doctor 能区分
  trusted/untrusted 并返回对应状态；运行过程未创建旧版
  `/tmp/term_enum_helper_v13`。
- 2026-07-28 回归：新增 SSH 命令参数与 Helper 路径引用测试，共 4 项 Rust
  测试通过；直接执行 Helper 可稳定复现本地 `untrusted`，验证权限主体差异。
  localhost 密码认证需在真实交互式终端由用户输入密码完成现场验收。

## 后续注意事项

- Helper 路径或二进制身份变化可能要求用户重新授权；正式安装应保持默认路径稳定。
- 不要把本机终端直接运行 Helper 的 `trusted` 结果当作手机 SSH 权限已经就绪；
  远端权限主体应在辅助功能列表中显示为 `sshd-keygen-wrapper`。
- 正式权限验收必须由用户亲自运行安装脚本并确认系统设置中的授权结果。
- 不要恢复运行时 Swift 编译，否则权限主体会再次变得不稳定。
