# 踩坑记录：Rust → HarmonyOS 工具链验证（termirror_core）

## 背景

- TermMirror 移动端改为「Rust 核心 + 三端原生 UI + C ABI FFI」架构，Rust 核心位于
  `MobileApp/shared/`（crate 名 `termirror_core`，独立 workspace，cdylib + rlib）。
- 目标：`aarch64-unknown-linux-ohos`（真机）与 `x86_64-unknown-linux-ohos`（模拟器）
  都能产出 `libtermirror_core.so`，并通过 NAPI 被 ArkTS 加载；SSH 走 `ssh2` crate。

## 关键结论

1. **OHOS linker 配置**：rustc 的 ohos target 需显式指定 OHOS NDK 的 clang 作为链接器，
   并传 `--target=<triple> --sysroot=<NDK>/sysroot`，配置在
   `MobileApp/shared/.cargo/config.toml`。NDK 根：
   `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/`
   （clang 在 `llvm/bin/clang`，sysroot 在 `sysroot`）。
2. **NAPI 链接方式**：在 `build.rs` 中按 target 输出
   `cargo:rustc-link-search=<NDK>/sysroot/usr/lib/{aarch64,x86_64}-linux-ohos` +
   `cargo:rustc-link-lib=dylib=ace_napi.z`。NAPI 模块入口直接导出
   `#[no_mangle] extern "C" fn napi_register_module_v1`（`src/ffi/napi.rs`），
   模块名约定 `termirror_core`，ArkTS 用 `import xxx from 'libtermirror_core.so'` 加载。
   NAPI 相关代码用 `#[cfg(target_env = "ohos")]` 隔离——注意 ohos target 的
   `target_os` 是 **"linux"**，必须匹配 `target_env = "ohos"`，host 侧 `cargo test` 不受影响。
3. **SSH 选型结论：ssh2 crate 可行**（libssh2 0.9.6 / libssh2-sys 0.3.2），
   通过 pkg-config 引用预编译的 `libssh2.a + libmbedcrypto.a`（mbedTLS 后端），
   无需备选的手写 extern 方案。
   - **依赖完全自包含于 `MobileApp/shared/` 内部**（2026-07-21 从已删除的
     `MobileClient/` 迁入，禁止再引用 MobileClient 任何路径）：
     源码 `third_party/{mbedtls,libssh2}`（浅克隆 pinned commit：mbedtls
     `22098d41`、libssh2 `a312b433`）、构建脚本 `scripts/build-ssh-dependencies.sh`、
     产物 `build/ohos-ssh/{arm64-v8a,x86_64}/`。
   - 描述文件：`MobileApp/shared/pkgconfig/<abi>/libssh2.pc`，用 `${pcfiledir}` 相对定位。
   - 构建入口：`MobileApp/shared/scripts/build-ohos.sh`，导出
     `LIBSSH2_SYS_USE_PKG_CONFIG=1`、`PKG_CONFIG_ALLOW_CROSS=1`、
     `PKG_CONFIG_PATH=<crate>/pkgconfig/<abi>`（按 ABI 切换），双 target 一次构建。
   - 验证：release cdylib 中静态链入 123 个 libssh2 符号 + 394 个 mbedtls 符号
     （release cdylib 会把非导出符号内部化为 local，nm 显示为小写 `t`，属正常现象）。
   - **注意**：修改 `.pc` 文件后必须删除
     `target/<triple>/release/build/libssh2-sys-*/` 缓存目录，否则 cargo 复用旧的
     build script 输出，链接器仍按旧路径找库（`cargo clean -p libssh2-sys` 可能清不干净）。

## 踩坑与解法

1. **libssh2-sys 错链 homebrew OpenSSL**。libssh2-sys 在 unix 下**强制依赖** openssl-sys
   （非可选），即使 pkg-config 已找到预编译 libssh2，openssl-sys 仍会在 macOS 上探测到
   homebrew OpenSSL 并发出 `-lssl -lcrypto`，交叉链接 ohos 目标时报
   `archive member ... is neither ET_REL nor LLVM bitcode`（架构不符）。
   **解法**：OHOS 预编译 libssh2 用 mbedTLS 后端，根本不需要 OpenSSL 符号。用
   `MobileApp/shared/third_party/openssl-stub/` 的桩头文件（`opensslv.h` 只定义
   `OPENSSL_VERSION_NUMBER`，供 openssl-sys 的 `build/expando.c` 版本探测）配合环境变量
   `OPENSSL_LIBS=""`（openssl-sys 支持该变量显式指定链接库列表，置空即不发出链接指令）、
   `OPENSSL_INCLUDE_DIR` / `OPENSSL_LIB_DIR` 指向 stub。此 trick 仅用于 OHOS 交叉构建，
   不影响 host 侧 `cargo test`。
2. **pkg-config 的 `${pcfiledir}` 相对层级算错**。`pkgconfig/arm64-v8a/libssh2.pc` 到仓库根
   是 4 级（`../../../..`），最初写成 3 级导致 `unable to find library -lssh2`。
   教训：先用 `pkg-config --libs libssh2` 打印并用 `ls` 验证路径，再跑 cargo。
3. **验证静态库是否链入时必须有导出符号引用**。最初自检函数
   `check_libssh2_available` 未被任何导出接口调用，release cdylib 死代码消除后
   libssh2.a 一个符号都没链入（此时链接也能"成功"，是假象）。已加 C ABI 导出
   `termirror_libssh2_check()`（`src/ffi/mod.rs`）真实引用 `ssh2::Session::new()`，
   并用 `llvm-nm` 确认符号链入。

## 影响范围

- 新增：`MobileApp/shared/`（crate 骨架、`.cargo/config.toml`、`build.rs`、
  `pkgconfig/`、`third_party/openssl-stub/`、`scripts/build-ohos.sh`）。
- 修改：根 `.gitignore` 增加 `/MobileApp/shared/target/`。
- 未改动：`PCServer/`、根 `Cargo.toml`。（`MobileClient/` 已于 2026-07-21 整体删除）

## 验证方式

- `cd MobileApp/shared && bash scripts/build-ohos.sh`：双 target release 构建成功，
  `file` 确认产物为 ELF 64-bit shared object（aarch64 / x86-64），
  `llvm-readelf -d` 确认 `NEEDED libace_napi.z.so`，
  `llvm-nm -D` 确认导出 `napi_register_module_v1` 与 `termirror_libssh2_check`。
- `cd MobileApp/shared && cargo test`：host（macOS）10 项单测全部通过，
  含 libssh2 初始化用例。

## 遗留问题

- `napi_register_module_v1` 的 ArkTS 侧真实加载与 `tm_add` 调用尚未在模拟器上验证
  （需 harmonyApp 侧工程接入后验收）。
- `.cargo/config.toml` 中 NDK 路径为本机绝对路径，换机器需调整（build.rs 的
  NAPI 路径可用 `HARMONY_NATIVE_SDK` 环境变量覆盖，linker 路径暂不可配）。
- openssl-stub 宣称的版本是 3.0.0；若未来启用真正依赖 OpenSSL 的 crate，需移除该桩。

## 补充（2026-07-21）：dlopen 静默失败——openssl-sys 未定义符号

**现象**：.so 已打进 HAP 且 napi_module_register 构造函数、.init_array 重定位均正常，但 ArkTS `import 'libtermirror_core.so'` 静默得到 undefined，App 降级 Mock 运行，hilog 无任何 dlopen 报错。

**根因**：libssh2-sys 在 unix 下 `init()` 会调 `openssl_sys::init()`（`lib.rs` platform_init），引用符号 `OPENSSL_init_ssl`。鸿蒙侧 libssh2 用 mbedtls 后端（`LIBSSH2_INIT_NO_CRYPTO`），不链接 OpenSSL，该符号未定义。Rust cdylib 带 BIND_NOW，dlopen 立即解析全部符号即失败；且链接期不报（cdylib 默认允许未定义符号），所以构建"成功"但运行时装不进来。

**排查手法**（通用）：`llvm-nm -D <so> | grep " U "` 列出未定义动态符号，与 sysroot 的 libc.so/libace_napi.z.so 已定义符号做 `comm -23` 差集，差集非空即 dlopen 必败。

**修复**：`src/session/openssl_shim.rs` 提供 `#[no_mangle] OPENSSL_init_ssl` 空实现（恒返回 1），cfg 限定 `target_env = "ohos"`，不影响 host。安全依据：libssh2 以 NO_CRYPTO 初始化，运行时不经过 OpenSSL。

**预防**：Rust 侧 C 依赖变更后，把"未定义动态符号差集为空"加入构建脚本检查（或链接加 `-z defs` 让问题在构建期暴露）。
