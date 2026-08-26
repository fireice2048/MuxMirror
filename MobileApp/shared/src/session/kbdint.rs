//! keyboard-interactive 认证回退。
//!
//! 背景：ssh2 crate 未暴露 `libssh2_userauth_keyboard_interactive_ex`，
//! 但不少服务器（PAM/OTP/SSSD 等）虽然声明支持 password 认证，
//! 实际上只有 keyboard-interactive 能通过（2026-07-21 真机实测 OpenSSH 10.2 案例）。
//! 这里直接走 libssh2-sys 实现回退：password 认证失败后再试 kbdint，
//! 对每个 prompt 统一用密码应答（覆盖最常见的 "Password:" 提示场景）。
//!
//! 内存约定（libssh2 userauth.c 源码确认）：回调为每个 response 分配的文本
//! 由 libssh2 用 LIBSSH2_FREE 释放，因此必须用 libc malloc 分配。

use std::cell::RefCell;
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_uint, c_void};

thread_local! {
    /// 当前线程进行 kbdint 认证时使用的密码（C 回调没有用户上下文参数，经线程局部传递）。
    static KBDINT_PASSWORD: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// keyboard-interactive 应答回调：每个 prompt 都填密码。
///
/// 由 libssh2 在 `libssh2_userauth_keyboard_interactive_ex` 调用期间同步回调；
/// responses 指向 libssh2 内部数组，按 num_prompts 填充，文本用 malloc 分配后交由 libssh2 释放。
extern "C" fn kbdint_response_cb(
    _username: *const c_char,
    _username_len: c_int,
    _instruction: *const c_char,
    _instruction_len: c_int,
    num_prompts: c_int,
    _prompts: *const libssh2_sys::LIBSSH2_USERAUTH_KBDINT_PROMPT,
    responses: *mut libssh2_sys::LIBSSH2_USERAUTH_KBDINT_RESPONSE,
    _abstrakt: *mut *mut c_void,
) {
    KBDINT_PASSWORD.with(|cell| {
        let borrow = cell.borrow();
        let password = match borrow.as_ref() {
            Some(p) => p,
            None => return,
        };
        let bytes = password.as_bytes_with_nul();
        for i in 0..num_prompts.max(0) as usize {
            let resp = unsafe { &mut *responses.add(i) };
            // 用 libc malloc 分配（libssh2 侧 LIBSSH2_FREE 释放，见模块注释）
            let buf = unsafe { libc::malloc(bytes.len()) as *mut c_char };
            if buf.is_null() {
                resp.text = std::ptr::null_mut();
                resp.length = 0;
                continue;
            }
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, bytes.len());
            }
            resp.text = buf;
            resp.length = (bytes.len() - 1) as c_uint; // 不含 NUL 结尾
        }
    });
}

/// keyboard-interactive 认证：对每个 prompt 用 `password` 应答。
///
/// 调用方需保证会话处于阻塞模式（本流程在 set_blocking(false) 之前调用）。
pub fn userauth_keyboard_interactive(
    sess: &ssh2::Session,
    username: &str,
    password: &str,
) -> Result<(), String> {
    let password_c =
        CString::new(password).map_err(|_| "密码含 NUL 字符，无法用于认证".to_string())?;
    let username_c =
        CString::new(username).map_err(|_| "用户名含 NUL 字符，无法用于认证".to_string())?;

    KBDINT_PASSWORD.with(|cell| *cell.borrow_mut() = Some(password_c));
    let rc = unsafe {
        libssh2_sys::libssh2_userauth_keyboard_interactive_ex(
            &mut *sess.raw(),
            username_c.as_ptr(),
            username_c.as_bytes().len() as c_uint,
            Some(kbdint_response_cb),
        )
    };
    KBDINT_PASSWORD.with(|cell| *cell.borrow_mut() = None);

    if rc == 0 {
        Ok(())
    } else {
        Err(format!("libssh2 错误码 {rc}"))
    }
}
