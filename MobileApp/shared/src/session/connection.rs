//! libssh2 可用性自检。
//!
//! 由 FFI 自检接口 `ffi::termirror_libssh2_check` 调用，
//! 用于验证静态库链接与运行时装载均正常。

/// 全局一次性完整初始化 libssh2（含加密后端初始化）。
///
/// 背景：ssh2 crate 的 `Session::new()` 走 libssh2-sys 的 unix 初始化路径，
/// 会以 `LIBSSH2_INIT_NO_CRYPTO` 调 `libssh2_init`（假定 OpenSSL 后端、由
/// openssl-sys 代为初始化加密）。但鸿蒙侧 libssh2 是 **mbedtls 后端**，
/// NO_CRYPTO 会跳过 mbedtls ctr_drbg 熵源播种，导致握手阶段
/// `_libssh2_mbedtls_random` 空指针 SIGSEGV（2026-07-21 模拟器实测，
/// 栈：mbedtls_ctr_drbg_reseed_internal ← _libssh2_mbedtls_random ← kex）。
///
/// 因此在任何 `ssh2::Session::new()` 之前先自行 `libssh2_init(0)` 完整初始化；
/// libssh2 内部有引用计数，ssh2 随后的 NO_CRYPTO 初始化不会重复初始化加密上下文。
pub fn ensure_libssh2_initialized() {
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        let rc = unsafe { libssh2_sys::libssh2_init(0) };
        assert_eq!(rc, 0, "libssh2_init(0) 失败：{rc}");
    });
}

/// 验证 libssh2 在目标平台可用：创建一个 libssh2 会话对象（不发起任何网络连接）。
///
/// `ssh2::Session::new()` 内部会完成 libssh2 全局初始化并调用
/// `libssh2_session_init_ex`，足以验证静态库链接与运行时装载均正常。
pub fn check_libssh2_available() -> Result<(), String> {
    ensure_libssh2_initialized();
    ssh2::Session::new()
        .map(|_| ())
        .map_err(|e| format!("libssh2 会话创建失败：{e}"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn libssh2可创建会话对象() {
        super::check_libssh2_available().expect("libssh2 不可用");
    }
}
