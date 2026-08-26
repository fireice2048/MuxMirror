//! OpenSSL 符号空实现（仅 ohos 目标）。
//!
//! 背景：libssh2-sys（ssh2 crate 的底层）在 unix 下初始化时会调用
//! `openssl_sys::init()` → `OPENSSL_init_ssl()`。但鸿蒙侧 libssh2 使用
//! mbedtls 作为加密后端（`libssh2_init(LIBSSH2_INIT_NO_CRYPTO)`），
//! 整个 .so 不链接任何 OpenSSL 库，导致 `OPENSSL_init_ssl` 成为未定义符号。
//!
//! 后果：cdylib 带 BIND_NOW 标志，dlopen 时立即解析全部符号，
//! 未定义符号使 dlopen 失败 → ArkTS `import 'libtermirror_core.so'`
//! 静默得到 undefined（2026-07-21 Pura 90 Pro New 模拟器实测排查）。
//!
//! 由于 libssh2 以 NO_CRYPTO 方式初始化、运行时完全不经过 OpenSSL，
//! 这里提供恒返回 1（成功）的空实现是安全的。

use std::os::raw::{c_int, c_void};

/// OpenSSL 1.1.0+ 初始化入口的空实现，恒返回 1（成功）。
///
/// # Safety
///
/// 仅填补链接缺口；libssh2 以 LIBSSH2_INIT_NO_CRYPTO 初始化，
/// 不会真正调用任何 OpenSSL 功能。
#[no_mangle]
pub unsafe extern "C" fn OPENSSL_init_ssl(_opts: u64, _settings: *const c_void) -> c_int {
    1
}
