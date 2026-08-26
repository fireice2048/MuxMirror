//! C ABI 导出层（薄层）。
//!
//! 只负责编解码与转发：把 Rust 核心的事件 / 数据模型暴露为稳定的 C ABI，
//! 不含任何业务逻辑。接口变更必须向后兼容，新增能力以新增接口方式扩展。
//!
//! - HarmonyOS：通过 [`napi`] 子模块导出 NAPI 模块 `termirror_core`，
//!   NAPI 函数与 C ABI 共用下方 `core_*` 实现；
//! - Android（JNI）/ iOS：直接使用下方 `tm_*` C 导出，签名见
//!   `ffi/include/termirror_core.h`（cbindgen 生成，`scripts/gen-header.sh`）。
//!
//! C ABI 字符串约定：入参为 NUL 结尾 UTF-8 字符串（调用方持有）；
//! 返回的 `*mut c_char` 由本库分配，调用方必须经 [`tm_string_free`] 释放。
//! 事件回调 `tm_on_event` 的 JSON 指针仅在回调调用期间有效，消费方需自行拷贝。

#[cfg(target_env = "ohos")]
pub mod napi;

use std::ffi::{c_char, c_int, CString};
use std::sync::RwLock;

use crate::config::{self, persist, store, ServerProfile};

/// 工具链验证用的最小纯函数：两数相加。
///
/// 通过 NAPI 导出为 `tm_add(a, b)`，用于验证
/// Rust → HarmonyOS 的编译、链接与 ArkTS 加载全链路。
pub fn tm_add(a: f64, b: f64) -> f64 {
    a + b
}

// ============================ core 层（NAPI 与 C ABI 共用） ============================

/// 核心初始化：日志系统 + 配置存储（契约 `tmInit`）。
pub fn core_init(files_dir: &str) {
    crate::log::init(files_dir, "TermMirror", crate::CORE_VERSION);
    if let Err(e) = crate::config::init(files_dir) {
        crate::tm_e!("配置存储初始化失败：{e}");
    }
}

/// 注册事件回调（契约 `tmOnEvent`）：接收结构化事件，覆盖旧回调。
pub fn core_set_event_sink<F>(sink: F)
where
    F: Fn(crate::session::TmEvent) + Send + Sync + 'static,
{
    crate::session::set_event_sink(sink);
}

/// 建立 SSH 会话（契约 `tmSessionConnect`）：同步返回 sessionId（>0），失败 -1。
pub fn core_session_connect(params_json: &str) -> i64 {
    crate::session::connect(params_json)
}

/// 写入会话输入（契约 `tmSessionWrite`）。
pub fn core_session_write(session_id: i64, data: &str) {
    crate::session::write(session_id, data);
}

/// 调整终端尺寸（契约 `tmSessionResize`）。
pub fn core_session_resize(session_id: i64, cols: u32, rows: u32) {
    crate::session::resize(session_id, cols, rows);
}

/// 执行一次性 SSH exec（契约 `tmSessionExec`）：同步返回 execId（>0），失败 -1。
/// stdout/错误经 `execResult` 事件异步上报（与 `connect` 同为后台线程 + 事件驱动）。
pub fn core_session_exec(params_json: &str, command: &str) -> i64 {
    crate::session::exec(params_json, command)
}

/// 关闭会话（契约 `tmSessionClose`）。
pub fn core_session_close(session_id: i64) {
    crate::session::close(session_id);
}

/// 按键编码（契约 `tmEncodeKey`）。
pub fn core_encode_key(key: &str, ctrl: bool, alt: bool) -> String {
    crate::input::encode_key(key, ctrl, alt)
}

/// 配置列表 JSON（契约 `tmConfigList`）。
pub fn core_config_list() -> String {
    crate::config::list_json().unwrap_or_else(|e| {
        crate::tm_e!("配置列表读取失败：{e}");
        "[]".to_string()
    })
}

/// 保存配置（契约 `tmConfigSave`）。
pub fn core_config_save(json: &str) {
    if let Err(e) = crate::config::save_json(json) {
        crate::tm_e!("配置保存失败：{e}");
    }
}

/// 删除配置（契约 `tmConfigDelete`）。
pub fn core_config_delete(name: &str) {
    if let Err(e) = crate::config::delete(name) {
        crate::tm_e!("配置删除失败：{e}");
    }
}

/// 移动配置并持久化顺序（契约 `tmConfigMove`）。
pub fn core_config_move(from: u32, to: u32) -> bool {
    match crate::config::move_item(from as usize, to as usize) {
        Ok(()) => true,
        Err(e) => {
            crate::tm_e!("配置排序保存失败：{e}");
            false
        }
    }
}

/// TCP 连通性诊断（契约 `tmTcpCheck`），结果经 diag 事件返回。
pub fn core_tcp_check(host: &str, port: u16) {
    crate::session::tcp_check(host, port);
}

// ============================ C ABI 导出（Android / iOS 备用） ============================

/// C 侧事件回调签名：参数为事件 JSON（NUL 结尾，仅回调期间有效）。
pub type TmEventCallback = Option<unsafe extern "C" fn(*const c_char)>;

static C_EVENT_CALLBACK: RwLock<Option<unsafe extern "C" fn(*const c_char)>> = RwLock::new(None);

/// 从 C 字符串读取 UTF-8 文本；空指针返回 None。
///
/// # 安全性
/// `ptr` 必须是有效的 NUL 结尾 UTF-8 字符串或空指针。
unsafe fn read_c_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    std::ffi::CStr::from_ptr(ptr).to_str().ok()
}

/// 把 Rust 字符串转为 C 堆字符串（调用方负责 `tm_string_free`）。
fn into_c_string(text: String) -> *mut c_char {
    // 剔除内部 NUL，保证 C 侧按 C 字符串语义读取
    CString::new(text.replace('\0', ""))
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// 初始化核心库（日志 + 配置）。`files_dir` 为应用文件目录。
///
/// # 安全性
/// `files_dir` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_init(files_dir: *const c_char) {
    if let Some(dir) = read_c_str(files_dir) {
        core_init(dir);
    }
}

/// 注册事件回调（JSON 字符串载荷），覆盖旧回调。
///
/// # 安全性
/// `callback` 指向的函数必须线程安全，且不得持有传入指针超过调用期。
#[no_mangle]
pub unsafe extern "C" fn tm_on_event(callback: TmEventCallback) {
    if let Ok(mut guard) = C_EVENT_CALLBACK.write() {
        *guard = callback;
    }
    core_set_event_sink(move |event| {
        let cb = C_EVENT_CALLBACK.read().ok().and_then(|g| *g);
        if let Some(cb) = cb {
            if let Ok(json) = serde_json::to_string(&event) {
                let c_json = into_c_string(json);
                if !c_json.is_null() {
                    cb(c_json);
                    tm_string_free(c_json);
                }
            }
        }
    });
}

/// 建立 SSH 会话，同步返回 sessionId（>0），失败 -1。
/// `params_json` 形如 `{"host":"","port":22,"username":"","password":"","cols":100,"rows":32}`。
///
/// # 安全性
/// `params_json` 必须是有效的 NUL 结尾 UTF-8 JSON 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_session_connect(params_json: *const c_char) -> i64 {
    match read_c_str(params_json) {
        Some(json) => core_session_connect(json),
        None => -1,
    }
}

/// 向会话写入输入数据。
///
/// # 安全性
/// `data` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_session_write(session_id: i64, data: *const c_char) {
    if let Some(text) = read_c_str(data) {
        core_session_write(session_id, text);
    }
}

/// 调整终端尺寸。
#[no_mangle]
pub extern "C" fn tm_session_resize(session_id: i64, cols: u32, rows: u32) {
    core_session_resize(session_id, cols, rows);
}

/// 执行一次性 SSH exec 命令，同步返回 execId（>0），失败 -1。
/// 结果（stdout / 错误信息）经 `execResult` 事件异步上报。
///
/// # 安全性
/// `params_json` / `command` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_session_exec(
    params_json: *const c_char,
    command: *const c_char,
) -> i64 {
    match (read_c_str(params_json), read_c_str(command)) {
        (Some(params), Some(cmd)) => core_session_exec(params, cmd),
        _ => -1,
    }
}

/// 关闭会话（幂等）。
#[no_mangle]
pub extern "C" fn tm_session_close(session_id: i64) {
    core_session_close(session_id);
}

/// 按键编码：返回终端字节序列（C 堆字符串，需 `tm_string_free` 释放）。
///
/// # 安全性
/// `key` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_encode_key(key: *const c_char, ctrl: bool, alt: bool) -> *mut c_char {
    match read_c_str(key) {
        Some(k) => into_c_string(core_encode_key(k, ctrl, alt)),
        None => std::ptr::null_mut(),
    }
}

/// 返回配置列表 JSON 数组（C 堆字符串，需 `tm_string_free` 释放）。
#[no_mangle]
pub extern "C" fn tm_config_list() -> *mut c_char {
    into_c_string(core_config_list())
}

/// 保存配置（按 name 新增或覆盖）。
///
/// # 安全性
/// `json` 必须是有效的 NUL 结尾 UTF-8 JSON 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_config_save(json: *const c_char) {
    if let Some(text) = read_c_str(json) {
        core_config_save(text);
    }
}

/// 按名称删除配置。
///
/// # 安全性
/// `name` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_config_delete(name: *const c_char) {
    if let Some(text) = read_c_str(name) {
        core_config_delete(text);
    }
}

/// 批量设置配置列表（调试用）：直接覆盖全部配置并落盘。
pub fn core_config_seed(json: &str) {
    if let Ok(profiles) = serde_json::from_str::<Vec<ServerProfile>>(json) {
        if let Ok(mut guard) = store() {
            guard.servers = profiles;
            if let Err(e) = persist(&guard) {
                crate::tm_e!("配置 seed 落盘失败：{e}");
            }
        }
    } else {
        crate::tm_e!("配置 seed JSON 解析失败");
    }
}

/// 移动配置并持久化顺序。
#[no_mangle]
pub extern "C" fn tm_config_move(from: u32, to: u32) -> bool {
    core_config_move(from, to)
}

/// TCP 连通性诊断（异步），结果经 diag 事件返回。
///
/// # 安全性
/// `host` 必须是有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn tm_tcp_check(host: *const c_char, port: u16) {
    if let Some(text) = read_c_str(host) {
        core_tcp_check(text, port);
    }
}

/// 释放本库分配的 C 字符串。
///
/// # 安全性
/// `ptr` 必须是本库返回的堆字符串指针，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn tm_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// C ABI：libssh2 运行时自检。
///
/// 返回 0 表示 libssh2 可正常初始化；非 0 表示不可用。
/// 除验证静态库真实链入 cdylib 外，也供三端启动时做环境自检。
#[no_mangle]
pub extern "C" fn termirror_libssh2_check() -> c_int {
    match crate::session::check_libssh2_available() {
        Ok(()) => 0,
        Err(_) => 1,
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn 两数相加() {
        assert_eq!(super::tm_add(1.5, 2.25), 3.75);
    }

    #[test]
    fn 按键编码core层() {
        assert_eq!(super::core_encode_key("UP", false, false), "\x1b[A");
        assert_eq!(super::core_encode_key("c", true, false), "\x03");
    }

    #[test]
    fn c字符串往返转换() {
        let raw = super::into_c_string("hello 终端".to_string());
        assert!(!raw.is_null());
        let back = unsafe { super::read_c_str(raw) }.unwrap();
        assert_eq!(back, "hello 终端");
        unsafe { super::tm_string_free(raw) };
    }

    #[test]
    fn libssh2自检返回零() {
        assert_eq!(super::termirror_libssh2_check(), 0);
    }
}
