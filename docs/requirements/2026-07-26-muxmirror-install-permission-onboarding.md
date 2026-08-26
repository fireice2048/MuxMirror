# muxmirror 安装期辅助功能权限引导

## 背景

macOS 版 muxmirror 通过 Accessibility API 枚举 Terminal、iTerm2 等终端窗口。当前程序首次执行时才在 `/tmp` 动态编译并运行 AX Helper；如果首次执行来自手机 SSH，权限提醒会延迟到远程连接时出现在电脑端，用户难以理解来源，也无法在安装阶段完成准备。

## 目标

- 安装 muxmirror 时部署路径稳定的 AX Helper。
- 安装流程在本机交互式会话中主动检查并申请辅助功能权限，打开系统设置并给出中文操作指引。
- 提供 `muxmirror setup` 和 `muxmirror doctor`，分别用于权限引导和状态诊断。
- 手机 SSH 远程执行 muxmirror 时不得主动弹出权限提醒；未授权时返回明确错误和本机修复命令。
- 清理旧版 `/tmp/term_enum_helper_v13` 及旧 muxmirror 安装，避免新旧权限主体混淆。

## 平台需求

### macOS

- AX Helper 安装到稳定的用户级目录，默认：
  `~/.local/libexec/muxmirror/muxmirror-ax-helper`。
- Helper 必须由安装脚本预编译，muxmirror 正常运行时不得在 `/tmp` 动态生成可执行文件。
- `setup` 必须由实际执行 AX 操作的稳定 Helper 调用
  `AXIsProcessTrustedWithOptions`，并使用系统 prompt 选项。
- 从本机终端执行 `setup` / `doctor` 时，必须通过 localhost SSH 运行
  Helper，使检查落在手机 SSH 同样使用的 `sshd-keygen-wrapper` 权限主体；
  已处于 SSH 会话时可直接检查。
- localhost SSH 应优先使用密码认证并禁用公钥尝试，避免本机加载过多密钥时
  在密码提示前触发 `Too many authentication failures`；命令必须继承终端
  输入输出，确保用户能够实际输入密码。
- 从本机终端执行普通窗口枚举时也必须通过 localhost SSH 运行 Helper，
  使本机与手机端统一落在 `sshd-keygen-wrapper` 权限主体，避免本机因终端
  自身未授权而误报无权限、手机端却可以正常枚举窗口。已处于 SSH 会话时
  直接运行 Helper，避免递归建立 localhost SSH 连接。
- 未授权时打开“系统设置 → 隐私与安全性 → 辅助功能”，打印 Helper 完整路径和授权后复检命令。
- `doctor` 只检查，不触发系统权限弹窗。

### Windows / Linux

- 保持当前终端窗口枚举能力和 mux 会话输出行为。
- `setup` / `doctor` 应说明该权限流程仅适用于 macOS，不影响默认扫描。

## 安装流程

1. 构建并安装 `muxmirror`。
2. 编译并部署稳定 AX Helper。
3. 执行 `muxmirror setup`，通过 localhost SSH 检查真实远端权限主体。
4. 若未授权，系统提醒用户并打开辅助功能设置。
5. 用户开启权限后执行 `muxmirror doctor` 或重新运行安装脚本。
6. doctor 通过后，本机与手机端窗口枚举均使用同一 SSH 权限主体。

## 错误行为

- Helper 缺失：提示重新运行安装脚本，不在运行时临时编译。
- 权限缺失：退出非零并提示在电脑端执行 `muxmirror setup`。
- Helper 执行失败：保留 stderr 诊断，不静默返回空窗口列表。
- localhost SSH 不可用或认证失败：提示检查远程登录、`AllowUsers` 和本机
  密码认证条件，不得误报为辅助功能未授权。

## 非目标

- 不绕过 macOS TCC，也不尝试静默替用户授予权限。
- 不重置其他应用已经获得的 Accessibility 权限。
- 本轮不制作签名 PKG、DMG 或 Homebrew Cask。

## 验收标准

1. 临时前缀安装时能生成 muxmirror 和稳定 AX Helper。
2. `muxmirror doctor` 能区分 Helper 缺失、未授权和已授权。
3. `muxmirror setup` 仅在本机显式执行时请求权限。
4. 正常扫描不再创建 `/tmp/term_enum_helper_v13`。
5. 旧 muxmirror 二进制和旧临时 Helper 被清理。
6. 用户亲自运行正式安装脚本并在系统设置中完成授权验收。
