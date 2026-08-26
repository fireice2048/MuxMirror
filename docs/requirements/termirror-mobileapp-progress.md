# TermMirror MobileApp 进度文档

起始日期：2026-07-20
需求文档：[2026-07-20-termirror-mobileapp.md](2026-07-20-termirror-mobileapp.md)
实施计划：见会话计划（M0 工具链验证 → M1 骨架 → M2 Rust 核心 → M3 ArkTS UI → M4 联调验收）

## 里程碑清单

### M0 工具链验证（spike）
- [x] 安装 `aarch64-unknown-linux-ohos` Rust target
- [x] 定位 OHOS SDK native 工具链（`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native`，含 clang + sysroot + `libace_napi.z.so`）
- [x] 配置 cargo linker，Rust cdylib 可编译到 ohos target（aarch64 + x86_64 双 target，`scripts/build-ohos.sh` 一键构建）
- [x] 最小 NAPI 模块（`tm_add`）编译成功（手写 napi_register_module_v1，无重型依赖）
- [x] `ssh2` crate 可交叉编译到 ohos target（pkg-config 复用 KMP 工程预编译 libssh2+mbedtls，openssl-stub 绕行 openssl-sys）
- [x] NAPI .so 打进鸿蒙工程，模拟器调用成功（端到端，2026-07-21 验证 Rust 核心真实加载）
- [x] 工具链结论记录到 `docs/memory/feedback/2026-07-20-rust-ohos-toolchain.md`

### M1 文档与工程骨架
- [x] 需求文档、进度文档
- [x] `MobileApp/shared/` crate 骨架（session/terminal/input/history/config/log + ffi，独立 workspace）
- [x] `MobileApp/harmonyApp/` 鸿蒙工程骨架（bundleName `com.termirror.mobile.harmony`，构建通过；**签名阻塞**：~/.ohos/config 下无匹配新包名的 p7b profile，需 DevEco Studio 自动签名生成一次）
- [ ] 更新 README.md、AGENTS.md（新路线说明，README 已加 MobileApp 条目，AGENTS.md 待补）

### M2 Rust 核心 MVP
- [x] C ABI 接口（`src/ffi/mod.rs`：tm_init / tm_on_event / tm_session_connect/write/resize/close / tm_encode_key / tm_config_list/save/delete / tm_tcp_check / tm_string_free；契约无 local_exec，以冻结 NAPI 契约为准）
- [x] cbindgen 头文件生成（`cbindgen.toml` + `scripts/gen-header.sh` → `ffi/include/termirror_core.h`，`build-ohos.sh` 自动调用；NAPI 内部声明用 `cbindgen:ignore` 排除）
- [x] SSH 会话（`src/session/`：密码认证、TCP 10s 超时、非阻塞读循环、后台线程、mpsc 命令通道、sessionId 自增多会话并存；kbdint 回退见遗留项）
- [x] ANSI 剥离 + `\r` 覆盖语义（`src/terminal/`：对齐 App.kt stripAnsiEscapeWithBuffer / appendTerminalOutput，UTF-8 跨块缓存，快照 256KB 截尾）
- [x] xterm 输入序列编码（`src/input/`：Ctrl 控制字符 / Alt 前缀 / 方向键与 HOME/END 修饰参数 / DEL、PGUP/PGDN、F1-F12）
- [x] YAML 服务器配置存取（`src/config/`：serde_yaml 落盘 `<filesDir>/servers.yaml`，JSON FFI 边界，按 name upsert/delete，Mutex 并发安全）
- [x] 日志模块（`src/log/`：Banner 注入式 / `TermMirror-YYYY-MM-DD.log` 按天滚动复打 Banner / 内存队列 + 写线程 FIFO / 2s 合并写盘 / 启动清理 30 天前日志 / tm_d! tm_i! tm_w! tm_e! 宏）
- [x] NAPI 事件桥（`src/ffi/napi.rs`：`napi_create_threadsafe_function` 把后台线程事件切回 JS 线程，TmEvent 对象字段对齐契约）
- [x] 单元测试（host `cargo test` 39 项全过；`bash scripts/build-ohos.sh` aarch64 + x86_64 双 target 构建成功）
- [x] 命令历史（`src/history/`：add / prev / next，对齐 shell 翻阅行为）

#### M2 遗留项
- [ ] keyboard-interactive 认证回退：ssh2 crate 未暴露 `libssh2_userauth_keyboard_interactive_ex`，MVP 仅密码认证；后续需手写 libssh2 extern 绑定或换 russh 评估
- [ ] 配置密码明文落盘 `servers.yaml`，加密存储待安全方案
- [ ] 日志 ohos 侧 hilog 输出未接（MVP 仅写文件）
- [ ] NAPI 端到端（ArkTS 真实加载 + SSH 直连）待 M4 联调验收

### M3 ArkTS UI 复刻
- [x] NAPI 薄封装 + 事件回调桥接 @State（`ets/core/TermirrorCore.ets`：类型化 API + 事件总线 + .so 缺失时 Mock 降级，全部页面可浏览）
- [x] 服务器列表页 + 新增/编辑/删除弹窗（ServerListPage + ServerEditDialog @CustomDialog + AlertDialog 删除确认，banner/加号按钮/行内编辑复制删除图标对齐蓝本）
- [x] 鸿蒙服务器列表复制按钮改为两个彩色剪贴板 Emoji 错位叠加，并完成 Pura 90 Pro 模拟器截图验收（复制确认弹窗正常）
- [x] 服务器列表长按拖动排序（ArkUI 原生浮起跟手/落位，新顺序持久化到 `servers.yaml`）
- [x] 终端页（标题栏/黑底绿字快照输出/闪烁光标/两行 20 键工具条/CTRL+ALT 锁定/⏏ 软键盘开关/隐藏 1dp 输入框/PasteButton 安全粘贴/10s 连接超时）
- [x] 网络诊断页（`tcp <IPv4> [端口]` 解析校验对齐蓝本，结果经 diag 事件回填）
- [x] 硬件按键转发（隐藏输入框 onKeyPreIme 拦截特殊键 → tmEncodeKey，可打印字符走文本输入；键值表对齐蓝本 HARMONY_KEYCODE_*）
- [x] `devecocli build` 编译 0 错误（9 条 WARN 为 may-throw/AlertDialog.show deprecated，不影响）；产出 unsigned HAP；SignHap 仍受 M1 签名材料缺失阻塞（已知）
- 备注：index.d.ts 已更新为完整冻结契约；与蓝本差异（本地光标模型简化、复制命名“原名 副本”）见 M3 汇报

### 集成（M2+M3 产物合并）
- [x] 双 ABI `libtermirror_core.so` 拷入 `entry/libs/{arm64-v8a,x86_64}/`（.so 为构建产物，已 gitignore 不入库）
- [x] `devecocli build` 通过，HAP 内确认含两个 ABI 的 .so
- 备注：按用户指示复用 MobileClient 签名材料，bundleName 沿用 `com.attach.mobile.harmony`；启用新包名需重新自动签名

### M4 联调验收
- [x] signed HAP 构建并安装到模拟器（Pura 90 Pro New，API 24）
- [x] NAPI 端到端：Rust 核心真实加载（修复 OPENSSL_init_ssl 未定义符号导致的静默 Mock）
- [x] SSH 全链路验证（asyncssh 测试桩 10.0.2.2:2222；修复 NO_CRYPTO 不播种熵源的握手崩溃）
- [x] 全功能自测：列表 CRUD/终端/软键盘抽查/工具条全 20 键/键盘动画/诊断页/粘贴/失败态，详见 `docs/acceptance/2026-07-21-termirror-harmony-selftest.md`
- [x] 修复问题 9 项（见验收记录表格），记忆文档新增 4 篇
- [ ] 横竖屏旋转（模拟器无法强制旋转，留人工验收）
