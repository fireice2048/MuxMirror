# TermMirror 鸿蒙版自测验收记录（2026-07-21）

- 环境：模拟器 Pura 90 Pro New（HarmonyOS 6.1.1，API 24，arm64）
- 被测包：`MobileApp/harmonyApp` entry-default-signed.hap（复用 com.attach.mobile.harmony 签名）
- SSH 测试桩：本机 asyncssh 服务器（127.0.0.1:2222，账号 test/test123，脚本 `/tmp/termirror_ssh_server.py`，venv `/tmp/termirror_ssh_venv`；启动：`/tmp/termirror_ssh_venv/bin/python /tmp/termirror_ssh_server.py`）
- 证据截图：`assets/selftest-20260720/`

## 验收清单

### 服务器列表页
- [x] 空列表渲染（banner/标题/+/网络诊断入口）— 01_list_native
- [x] 新增：弹窗 5 字段、空地址/空用户保存被拦截、密码 🙈→👁 明文切换 — 05_list_with_server
- [x] 端口默认值 22 可修改；YAML 持久化（重启 App 配置仍在）
- [x] 编辑：弹窗回填正确；改名保存不重复（修复了改名产生重复项的 bug：改名时先删旧名称条目）
- [x] 复制：生成"原名 副本"
- [x] 删除：确认弹窗 取消/删除 两分支 — 06_delete_confirm

### SSH 终端
- [x] 连接成功：标题栏（名称 + ssh user@host:port）、黑底绿字、bash 提示符、闪烁光标 — 11_conn_2
- [x] 命令执行：`ls`/`ls /usr/bin` 输出正确（服务端日志逐字节核对）；长输出 8268 字符正常 — 24_ls_result
- [x] 连接失败态：TCP 拒连"TCP 连接失败：Connection refused" — 52_failtest_failed；密码错误"认证失败：[Session(-18)]" — 53_badauth
- [x] 返回键回列表（会话关闭）

### 软键盘（抽查 >10 键）
- [x] 字母 e/c/h/o/i/l/s/u/r/b/n/p/w/d/a、数字 4/8/0、符号 ./空格 逐键验证入缓冲
- [x] 首字母自动大写缺陷修复（USER_NAME 键盘 + 空字段大写抑制），`ls /usr/bin` 完整输入
- [x] 退格删除；发送执行；发送后键盘保持不收起（新增 requestFocus）— 28_keyboard_stays

### 工具条（全 20 键，服务端日志逐字节核对）
- [x] `/ - : * |` 入本地缓冲并随行发送（`:/-:*|` 服务端收到）
- [x] ESC/TAB 直发 `\x1b`/`\t`；HOME/END/方向键/DEL 发 xterm 序列（含修饰参数 1;3/1;5 等）
- [x] CTRL/ALT 锁定态绿底白字（31_ctrl_lock_visual），Ctrl+C=\x03、Ctrl+X=\x18、Alt+Ctrl+X=ESC+\x18 均正确 — 33_ctrl_c_clean
- [x] PGUP/PGDN 本地滚动 — 42_pgup
- [x] ⏏ 收起/唤起键盘，翻转动画正常
- [x] 粘贴 PasteButton：空剪贴板无异常；从诊断页复制后粘贴完整文本入缓冲 — 46_pasted
- [x] 键盘弹收动画：工具条全程贴合键盘上沿，中间帧无跳动/留白/重叠 — 34_kbd_hiding_mid / 35_kbd_hidden / 50_show_done

### 网络诊断页
- [x] 非法输入中文提示（"仅支持 TCP 检测。用法：tcp <IPv4> [端口]"）— 45_diag_page
- [x] `tcp 10.0.2.2 2222` 可达（RTT≈3ms）；`tcp 10.0.2.2 1` 不可达（Connection refused）
- [x] 复制终端内容按钮；返回列表

### 其他
- [x] 硬件回车注入（keyEvent 2054）生效
- [x] 输入管线：隐藏输入框改"IME 增量消费"模型，工具条与软键盘混输不互冲
- [ ] 横竖屏旋转：模拟器镜像无 settings 命令，未能强制旋转，留待人工验收覆盖

## 自测中修复的问题（均已回归）

| 问题 | 根因 | 修复 |
|---|---|---|
| 启动闪退 | loadContent 完成前调 getUIContext | 移入回调（记忆 2026-07-20-entryability-getuicontext-jscrash） |
| .so 加载失败静默 Mock | openssl-sys 引用 OPENSSL_init_ssl 未定义，BIND_NOW dlopen 失败 | Rust 空实现补符号（记忆 2026-07-20-rust-ohos-toolchain） |
| SSH 握手 SIGSEGV | ssh2 的 NO_CRYPTO 初始化不播种 mbedtls 熵源 | 先完整 libssh2_init(0) |
| "transport read" 误报 | 测试桩 asyncssh 未处理 resize 异常关连接 | 测试桩修复（记忆 2026-07-21-asyncssh-test-server-pitfalls） |
| 命令回显两遍 | asyncssh line_editor 协议层回显 | line_editor=False（同上） |
| 编辑改名产生重复项 | 按名称 upsert 未删旧条目 | Index.ets 改名先 deleteConfig |
| 首字母大写/空格被吞 | 小艺输入法 + InputType 副作用 | USER_NAME + normalizeImeCapital（记忆 2026-07-21-harmony-terminal-ime-input-pitfalls） |
| 工具条与软键盘互冲 | TextInput text 绑定聚焦时不生效 | 隐藏输入框改增量消费模型（同上） |
| 发送后键盘收起 | IME Send 动作默认收键盘 | sendInput 后 requestFocus |

## 遗留/人工验收提示

1. 横竖屏旋转未覆盖。
2. kbdint 认证方式未实现（ssh2 crate 限制，MVP 仅密码认证）。
3. 软键盘首字母大写抑制是启发式（空字段单大写字母转小写），用户在空字段故意输大写需先打任意字符。
4. 人工验收前请确认 asyncssh 测试桩已启动（见上文命令），或改用真实 SSH 服务器。

## 人工验收反馈与二轮修复（2026-07-21）

| 反馈问题 | 根因 | 修复 | 回归 |
|---|---|---|---|
| 光标键/HOME/END 无效 | caret 非 @State，移动不触发渲染 | caret 改 @State | ←→/HOME/END 光标块可见移动 ✓ |
| DEL 在末尾添加乱码 | 末尾时误走 writeRemoteAction 把缓冲发远端 | 末尾不动作；光标中段正确前向删除 | HOME+DEL 删首字符、END+DEL 无动作 ✓ |
| ⏏ 偶尔按两次 | IME 自带按钮收键盘后请求标记残留 | keyboardHeightChange 为 0 时清标记 | IME 收起后单点 ⏏ 一次唤起 ✓ |
| 软键盘 backspace 无效 | 组件空时 IME 退格无回调；空缓冲无远端退格路径 | 空缓冲 onKeyPreIme 发 \x7f 到远端 | 硬件/事件注入退格服务端收 \x7f ✓；输入中文本退格正常 ✓ |
| PGUP/PGDN 无效 | 本地滚动仅在内容超屏时生效（短内容无可滚） | 设计如此（对齐蓝本），长输出下已验证 ✓ | 42_pgup/43_pgdn |

回归证据：57_regression_final（ls→退格→工具条/→软键盘s→←→DEL→END→发送 全链路）；混输不再互冲。

## 人工验收反馈第三轮（2026-07-21）

| 反馈问题 | 根因 | 修复 | 回归 |
|---|---|---|---|
| 终端页盖住系统状态栏，返回按钮无法点击 | 沉浸式布局（setWindowLayoutFullScreen）下未做安全区避让（蓝本 safeDrawingPadding 效果缺失） | EntryAbility 读取 TYPE_SYSTEM 避让区高度注入 AppStorage，Index 根容器加顶部 padding | 三页标题栏均在状态栏下方，返回可点击 ✓（59_terminal_safearea） |
