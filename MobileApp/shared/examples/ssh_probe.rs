//! kbdint 回退探针：对 127.0.0.1:2223（仅 kbdint 服务器）验证回调路径。
use std::cell::RefCell;
use std::ffi::CString;
use std::net::{TcpStream, ToSocketAddrs};
use std::os::raw::{c_char, c_int, c_uint, c_void};
use std::time::Duration;

thread_local! {
    static KBDINT_PASSWORD: RefCell<Option<CString>> = const { RefCell::new(None) };
}

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
    println!("[probe] kbdint 回调被调用 num_prompts={num_prompts}");
    KBDINT_PASSWORD.with(|cell| {
        let borrow = cell.borrow();
        let password = match borrow.as_ref() {
            Some(p) => p,
            None => {
                println!("[probe] 线程局部密码为空！");
                return;
            }
        };
        let bytes = password.as_bytes_with_nul();
        for i in 0..num_prompts.max(0) as usize {
            let resp = unsafe { &mut *responses.add(i) };
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
            resp.length = (bytes.len() - 1) as c_uint;
        }
        println!("[probe] 已填充应答");
    });
}

fn main() {
    let addr = "127.0.0.1:2223";
    let sock = addr.to_socket_addrs().unwrap().next().unwrap();
    let tcp = TcpStream::connect_timeout(&sock, Duration::from_secs(5)).expect("TCP 失败");
    let mut sess = ssh2::Session::new().expect("libssh2 初始化失败");
    sess.set_tcp_stream(tcp);
    sess.handshake().expect("握手失败");
    println!("握手成功: {:?}", sess.banner());

    // 跳过 password，直接 kbdint

    // kbdint 回退
    let password_c = CString::new("test123").unwrap();
    let username_c = CString::new("test").unwrap();
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
    println!("kbdint rc={rc} authenticated={}", sess.authenticated());
}
