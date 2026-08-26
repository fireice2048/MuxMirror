//! HarmonyOS NAPI 模块导出（仅 OHOS target 编译）。
//!
//! 直接手写 NAPI C API 的 extern 调用（头文件：`napi/native_api.h`、`node_api.h`），
//! 不引入 napi-rs 等重型依赖。ArkTS 侧加载方式：
//!
//! ```ts
//! import termirrorCore from 'libtermirror_core.so';
//! termirrorCore.tmInit(this.context.filesDir);
//! ```
//!
//! ArkTS 运行时装载 .so 后会查找并调用导出符号 `napi_register_module_v1`，
//! 本模块在该入口中把全部契约函数挂到 exports 对象上。
//!
//! 事件桥：会话/诊断事件由 Rust 后台线程产生，经
//! `napi_create_threadsafe_function` 切回 JS 线程回调（契约要求）。

use std::ffi::{c_char, c_double, c_void, CString};
use std::ptr;
use std::sync::RwLock;

#[allow(non_camel_case_types)]
type napi_env = *mut c_void;
#[allow(non_camel_case_types)]
type napi_value = *mut c_void;
#[allow(non_camel_case_types)]
type napi_callback_info = *mut c_void;
#[allow(non_camel_case_types)]
type napi_status = i32;
#[allow(non_camel_case_types)]
type napi_callback = Option<unsafe extern "C" fn(napi_env, napi_callback_info) -> napi_value>;
#[allow(non_camel_case_types)]
type napi_threadsafe_function = *mut c_void;
#[allow(non_camel_case_types)]
type napi_threadsafe_function_call_js =
    Option<unsafe extern "C" fn(napi_env, napi_value, *mut c_void, *mut c_void)>;

const NAPI_OK: napi_status = 0;
/// napi_threadsafe_function_call_mode：非阻塞投递
const NAPI_TSFN_NONBLOCKING: i32 = 0;
/// napi_threadsafe_function_release_mode：立即释放
const NAPI_TSFN_RELEASE: i32 = 0;

// NAPI C API（由 libace_napi.z.so 提供，链接方式见 build.rs）
/// cbindgen:ignore
#[allow(unused_doc_comments)]
extern "C" {
    fn napi_create_function(
        env: napi_env,
        utf8name: *const c_char,
        length: usize,
        cb: napi_callback,
        data: *mut c_void,
        result: *mut napi_value,
    ) -> napi_status;
    fn napi_set_named_property(
        env: napi_env,
        object: napi_value,
        utf8name: *const c_char,
        value: napi_value,
    ) -> napi_status;
    fn napi_get_cb_info(
        env: napi_env,
        cbinfo: napi_callback_info,
        argc: *mut usize,
        argv: *mut napi_value,
        this_arg: *mut napi_value,
        data: *mut *mut c_void,
    ) -> napi_status;
    fn napi_call_function(
        env: napi_env,
        recv: napi_value,
        func: napi_value,
        argc: usize,
        argv: *const napi_value,
        result: *mut napi_value,
    ) -> napi_status;
    fn napi_get_undefined(env: napi_env, result: *mut napi_value) -> napi_status;
    fn napi_create_object(env: napi_env, result: *mut napi_value) -> napi_status;
    fn napi_create_array_with_length(
        env: napi_env,
        length: usize,
        result: *mut napi_value,
    ) -> napi_status;
    fn napi_set_element(
        env: napi_env,
        object: napi_value,
        index: u32,
        value: napi_value,
    ) -> napi_status;
    fn napi_get_value_double(
        env: napi_env,
        value: napi_value,
        result: *mut c_double,
    ) -> napi_status;
    fn napi_create_double(env: napi_env, value: c_double, result: *mut napi_value) -> napi_status;
    fn napi_get_value_int64(env: napi_env, value: napi_value, result: *mut i64) -> napi_status;
    fn napi_create_int64(env: napi_env, value: i64, result: *mut napi_value) -> napi_status;
    fn napi_get_value_uint32(env: napi_env, value: napi_value, result: *mut u32) -> napi_status;
    fn napi_get_value_bool(env: napi_env, value: napi_value, result: *mut bool) -> napi_status;
    fn napi_get_boolean(env: napi_env, value: bool, result: *mut napi_value) -> napi_status;
    fn napi_get_value_string_utf8(
        env: napi_env,
        value: napi_value,
        buf: *mut c_char,
        bufsize: usize,
        result: *mut usize,
    ) -> napi_status;
    fn napi_create_string_utf8(
        env: napi_env,
        str_: *const c_char,
        length: usize,
        result: *mut napi_value,
    ) -> napi_status;
    fn napi_create_threadsafe_function(
        env: napi_env,
        func: napi_value,
        async_resource: napi_value,
        async_resource_name: napi_value,
        max_queue_size: usize,
        initial_thread_count: usize,
        thread_finalize_data: *mut c_void,
        thread_finalize_cb: *mut c_void,
        context: *mut c_void,
        call_js_cb: napi_threadsafe_function_call_js,
        result: *mut napi_threadsafe_function,
    ) -> napi_status;
    fn napi_call_threadsafe_function(
        func: napi_threadsafe_function,
        data: *mut c_void,
        is_blocking: i32,
    ) -> napi_status;
    fn napi_release_threadsafe_function(func: napi_threadsafe_function, mode: i32) -> napi_status;
}

// ============================ 基础工具 ============================

/// 读取 NAPI string 参数为 Rust String。
unsafe fn get_string(env: napi_env, value: napi_value) -> String {
    let mut len = 0usize;
    if napi_get_value_string_utf8(env, value, ptr::null_mut(), 0, &mut len) != NAPI_OK {
        return String::new();
    }
    let mut buf = vec![0u8; len + 1];
    if napi_get_value_string_utf8(
        env,
        value,
        buf.as_mut_ptr() as *mut c_char,
        buf.len(),
        &mut len,
    ) != NAPI_OK
    {
        return String::new();
    }
    buf.truncate(len);
    String::from_utf8(buf).unwrap_or_default()
}

/// 创建 NAPI string。
unsafe fn make_string(env: napi_env, text: &str) -> napi_value {
    let mut result: napi_value = ptr::null_mut();
    napi_create_string_utf8(env, text.as_ptr() as *const c_char, text.len(), &mut result);
    result
}

/// 创建 NAPI boolean。
unsafe fn make_bool(env: napi_env, value: bool) -> napi_value {
    let mut result: napi_value = ptr::null_mut();
    napi_get_boolean(env, value, &mut result);
    result
}

/// 读取 NAPI number 为 i64。
unsafe fn get_i64(env: napi_env, value: napi_value) -> i64 {
    let mut result = 0i64;
    napi_get_value_int64(env, value, &mut result);
    result
}

/// 读取 NAPI number 为 u32。
unsafe fn get_u32(env: napi_env, value: napi_value) -> u32 {
    let mut result = 0u32;
    napi_get_value_uint32(env, value, &mut result);
    result
}

/// 读取 NAPI boolean。
unsafe fn get_bool(env: napi_env, value: napi_value) -> bool {
    let mut result = false;
    napi_get_value_bool(env, value, &mut result);
    result
}

/// 创建 NAPI undefined。
unsafe fn undefined(env: napi_env) -> napi_value {
    let mut result: napi_value = ptr::null_mut();
    napi_get_undefined(env, &mut result);
    result
}

/// 读取回调参数：返回 (参数数组, 实际个数)，最多 MAX 个。
unsafe fn get_args<const MAX: usize>(
    env: napi_env,
    info: napi_callback_info,
) -> ([napi_value; MAX], usize) {
    let mut argc = MAX;
    let mut argv: [napi_value; MAX] = [ptr::null_mut(); MAX];
    napi_get_cb_info(
        env,
        info,
        &mut argc,
        argv.as_mut_ptr(),
        ptr::null_mut(),
        ptr::null_mut(),
    );
    (argv, argc.min(MAX))
}

// ============================ 事件桥（TSFN） ============================

/// 跨线程安全传递的 TSFN 指针包装。
struct SendTsfn(napi_threadsafe_function);
unsafe impl Send for SendTsfn {}
unsafe impl Sync for SendTsfn {}

static EVENT_TSFN: RwLock<Option<SendTsfn>> = RwLock::new(None);

/// 投递给 JS 线程的事件载荷。
struct NapiEvent {
    session_id: i64,
    event_type: CString,
    state: Option<CString>,
    data: Option<CString>,
    cursor: Option<i64>,
    styles: Vec<crate::terminal::TerminalStyleRange>,
    mouse_protocol: Option<CString>,
}

/// TSFN 的 JS 线程回调：把事件组装成 TmEvent 对象并调用 ArkTS 回调。
unsafe extern "C" fn event_call_js(
    env: napi_env,
    js_cb: napi_value,
    _context: *mut c_void,
    data: *mut c_void,
) {
    if data.is_null() {
        return;
    }
    let event = Box::from_raw(data as *mut NapiEvent);
    if js_cb.is_null() {
        return;
    }

    let mut obj: napi_value = ptr::null_mut();
    napi_create_object(env, &mut obj);

    let mut id_value: napi_value = ptr::null_mut();
    napi_create_int64(env, event.session_id, &mut id_value);
    napi_set_named_property(env, obj, c"sessionId".as_ptr(), id_value);
    let type_value = make_string(env, event.event_type.to_str().unwrap_or("error"));
    napi_set_named_property(env, obj, c"type".as_ptr(), type_value);
    if let Some(state) = &event.state {
        let value = make_string(env, state.to_str().unwrap_or(""));
        napi_set_named_property(env, obj, c"state".as_ptr(), value);
    }
    if let Some(data) = &event.data {
        let value = make_string(env, data.to_str().unwrap_or(""));
        napi_set_named_property(env, obj, c"data".as_ptr(), value);
    }
    if let Some(cursor) = event.cursor {
        let mut cursor_value: napi_value = ptr::null_mut();
        napi_create_int64(env, cursor, &mut cursor_value);
        napi_set_named_property(env, obj, c"cursor".as_ptr(), cursor_value);
    }
    if !event.styles.is_empty() {
        let mut array: napi_value = ptr::null_mut();
        napi_create_array_with_length(env, event.styles.len(), &mut array);
        for (index, style) in event.styles.iter().enumerate() {
            let mut item: napi_value = ptr::null_mut();
            napi_create_object(env, &mut item);
            let mut start: napi_value = ptr::null_mut();
            napi_create_int64(env, style.start as i64, &mut start);
            napi_set_named_property(env, item, c"start".as_ptr(), start);
            let mut end: napi_value = ptr::null_mut();
            napi_create_int64(env, style.end as i64, &mut end);
            napi_set_named_property(env, item, c"end".as_ptr(), end);
            let style_value = make_string(env, style.style);
            napi_set_named_property(env, item, c"style".as_ptr(), style_value);
            if let Some(foreground) = &style.foreground {
                let value = make_string(env, foreground);
                napi_set_named_property(env, item, c"foreground".as_ptr(), value);
            }
            if let Some(background) = &style.background {
                let value = make_string(env, background);
                napi_set_named_property(env, item, c"background".as_ptr(), value);
            }
            napi_set_element(env, array, index as u32, item);
        }
        napi_set_named_property(env, obj, c"styles".as_ptr(), array);
    }
    if let Some(mouse_protocol) = &event.mouse_protocol {
        let value = make_string(env, mouse_protocol.to_str().unwrap_or("none"));
        napi_set_named_property(env, obj, c"mouseProtocol".as_ptr(), value);
    }

    let recv = undefined(env);
    let argv = [obj];
    napi_call_function(env, recv, js_cb, 1, argv.as_ptr(), ptr::null_mut());
}

/// 契约 `tmOnEvent(cb)`：注册全局事件回调（TSFN 桥接，覆盖旧回调）。
unsafe extern "C" fn tm_on_event(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        let name = make_string(env, "termirror_events");
        let mut tsfn: napi_threadsafe_function = ptr::null_mut();
        let status = napi_create_threadsafe_function(
            env,
            argv[0],
            ptr::null_mut(),
            name,
            0, // 队列无上限
            1, // 单 JS 线程
            ptr::null_mut(),
            ptr::null_mut(),
            ptr::null_mut(),
            Some(event_call_js),
            &mut tsfn,
        );
        if status == NAPI_OK && !tsfn.is_null() {
            // 释放旧 TSFN 再替换
            let old = EVENT_TSFN
                .write()
                .ok()
                .and_then(|mut g| g.replace(SendTsfn(tsfn)));
            if let Some(old) = old {
                napi_release_threadsafe_function(old.0, NAPI_TSFN_RELEASE);
            }
            super::core_set_event_sink(|event| {
                let tsfn = EVENT_TSFN.read().ok().and_then(|g| g.as_ref().map(|s| s.0));
                if let Some(tsfn) = tsfn {
                    let payload = Box::new(NapiEvent {
                        session_id: event.session_id,
                        event_type: CString::new(event.event_type)
                            .unwrap_or_else(|_| CString::new("error").unwrap()),
                        state: event.state.and_then(|s| CString::new(s).ok()),
                        data: event.data.and_then(|d| CString::new(d).ok()),
                        cursor: event.cursor,
                        styles: event.styles.unwrap_or_default(),
                        mouse_protocol: event
                            .mouse_protocol
                            .and_then(|protocol| CString::new(protocol).ok()),
                    });
                    napi_call_threadsafe_function(
                        tsfn,
                        Box::into_raw(payload) as *mut c_void,
                        NAPI_TSFN_NONBLOCKING,
                    );
                }
            });
        }
    }
    undefined(env)
}

// ============================ 契约函数 ============================

/// 契约 `tmInit(filesDir)`：初始化日志与配置存储。
unsafe extern "C" fn tm_init(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        let files_dir = get_string(env, argv[0]);
        super::core_init(&files_dir);
    }
    undefined(env)
}

/// 契约 `tmSessionConnect(paramsJson)`：同步返回 sessionId（>0），失败 -1。
unsafe extern "C" fn tm_session_connect(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    let session_id = if argc >= 1 {
        let params = get_string(env, argv[0]);
        super::core_session_connect(&params)
    } else {
        -1
    };
    let mut result: napi_value = ptr::null_mut();
    napi_create_int64(env, session_id, &mut result);
    result
}

/// 契约 `tmSessionWrite(sessionId, data)`。
unsafe extern "C" fn tm_session_write(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<2>(env, info);
    if argc >= 2 {
        let session_id = get_i64(env, argv[0]);
        let data = get_string(env, argv[1]);
        super::core_session_write(session_id, &data);
    }
    undefined(env)
}

/// 契约 `tmSessionResize(sessionId, cols, rows)`。
unsafe extern "C" fn tm_session_resize(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<3>(env, info);
    if argc >= 3 {
        let session_id = get_i64(env, argv[0]);
        let cols = get_u32(env, argv[1]);
        let rows = get_u32(env, argv[2]);
        super::core_session_resize(session_id, cols, rows);
    }
    undefined(env)
}

/// 契约 `tmSessionExec(paramsJson, command)`：同步返回 execId（>0），失败 -1。
/// stdout/错误经 `execResult` 事件异步上报（与 connect 同为事件驱动）。
unsafe extern "C" fn tm_session_exec(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<2>(env, info);
    let exec_id = if argc >= 2 {
        let params = get_string(env, argv[0]);
        let command = get_string(env, argv[1]);
        super::core_session_exec(&params, &command)
    } else {
        -1
    };
    let mut result: napi_value = ptr::null_mut();
    napi_create_int64(env, exec_id, &mut result);
    result
}

/// 契约 `tmSessionClose(sessionId)`。
unsafe extern "C" fn tm_session_close(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        super::core_session_close(get_i64(env, argv[0]));
    }
    undefined(env)
}

/// 契约 `tmEncodeKey(key, ctrl, alt)`：返回终端字节序列字符串。
unsafe extern "C" fn tm_encode_key(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<3>(env, info);
    if argc >= 3 {
        let key = get_string(env, argv[0]);
        let ctrl = get_bool(env, argv[1]);
        let alt = get_bool(env, argv[2]);
        make_string(env, &super::core_encode_key(&key, ctrl, alt))
    } else {
        make_string(env, "")
    }
}

/// 契约 `tmConfigList()`：返回配置 JSON 数组字符串。
unsafe extern "C" fn tm_config_list(env: napi_env, _info: napi_callback_info) -> napi_value {
    make_string(env, &super::core_config_list())
}

/// 契约 `tmConfigSave(json)`：按 name 新增或覆盖。
unsafe extern "C" fn tm_config_save(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        let json = get_string(env, argv[0]);
        super::core_config_save(&json);
    }
    undefined(env)
}

/// 契约 `tmConfigDelete(name)`。
unsafe extern "C" fn tm_config_delete(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        let name = get_string(env, argv[0]);
        super::core_config_delete(&name);
    }
    undefined(env)
}

/// 批量设置配置列表（调试用）：直接覆盖全部配置并落盘。
/// `json` 为 `ServerConfig[]` 的 JSON 数组字符串。
unsafe extern "C" fn tm_config_seed(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<1>(env, info);
    if argc >= 1 {
        let json = get_string(env, argv[0]);
        super::core_config_seed(&json);
    }
    undefined(env)
}

/// 契约 `tmConfigMove(from, to)`：移动配置并返回持久化结果。
unsafe extern "C" fn tm_config_move(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<2>(env, info);
    if argc < 2 {
        return make_bool(env, false);
    }
    make_bool(
        env,
        super::core_config_move(get_u32(env, argv[0]), get_u32(env, argv[1])),
    )
}

/// 契约 `tmTcpCheck(host, port)`：异步诊断，结果经 diag 事件返回。
unsafe extern "C" fn tm_tcp_check(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<2>(env, info);
    if argc >= 2 {
        let host = get_string(env, argv[0]);
        let port = get_u32(env, argv[1]) as u16;
        super::core_tcp_check(&host, port);
    }
    undefined(env)
}

/// 自检 `tm_add(a, b)`：两数相加（工具链验证用，保留）。
unsafe extern "C" fn tm_add(env: napi_env, info: napi_callback_info) -> napi_value {
    let (argv, argc) = get_args::<2>(env, info);
    let mut values = [0.0f64; 2];
    for (i, value) in values.iter_mut().enumerate().take(argc.min(2)) {
        napi_get_value_double(env, argv[i], value);
    }
    let mut result: napi_value = ptr::null_mut();
    napi_create_double(env, super::tm_add(values[0], values[1]), &mut result);
    result
}

// ============================ 模块入口 ============================

/// 全部导出函数表：(导出名, 函数指针)。
const EXPORTS: &[(&[u8], napi_callback)] = &[
    (b"tm_add\0", Some(tm_add)),
    (b"tmOnEvent\0", Some(tm_on_event)),
    (b"tmInit\0", Some(tm_init)),
    (b"tmSessionConnect\0", Some(tm_session_connect)),
    (b"tmSessionWrite\0", Some(tm_session_write)),
    (b"tmSessionResize\0", Some(tm_session_resize)),
    (b"tmSessionExec\0", Some(tm_session_exec)),
    (b"tmSessionClose\0", Some(tm_session_close)),
    (b"tmEncodeKey\0", Some(tm_encode_key)),
    (b"tmConfigList\0", Some(tm_config_list)),
    (b"tmConfigSave\0", Some(tm_config_save)),
    (b"tmConfigDelete\0", Some(tm_config_delete)),
    (b"tmConfigSeed\0", Some(tm_config_seed)),
    (b"tmConfigMove\0", Some(tm_config_move)),
    (b"tmTcpCheck\0", Some(tm_tcp_check)),
];

/// NAPI 模块入口：ArkTS 装载 `libtermirror_core.so` 时由运行时调用。
///
/// 模块名约定为 `termirror_core`（与 .so 文件名 `libtermirror_core.so` 对应）。
/// cbindgen:ignore
#[no_mangle]
pub unsafe extern "C" fn napi_register_module_v1(env: napi_env, exports: napi_value) -> napi_value {
    for (name, callback) in EXPORTS {
        let mut func: napi_value = ptr::null_mut();
        let status = napi_create_function(
            env,
            name.as_ptr() as *const c_char,
            name.len() - 1,
            *callback,
            ptr::null_mut(),
            &mut func,
        );
        if status != NAPI_OK || func.is_null() {
            continue;
        }
        napi_set_named_property(env, exports, name.as_ptr() as *const c_char, func);
    }
    exports
}

// ---------------------------------------------------------------------------
// napi_module 构造函数注册（与 NDK C++ 模板一致的主路径）
// ---------------------------------------------------------------------------
//
// 模拟器实测：`import x from 'libtermirror_core.so'` 时运行时只认
// `napi_module_register`（构造函数 + nm_modname）注册的模块，仅导出
// `napi_register_module_v1` 不会被调用，import 结果为 undefined。
// 这里复刻 NDK 模板 napi_init.cpp 的注册方式。

/// node_api.h 的 napi_module 结构体布局。
/// cbindgen:ignore
#[repr(C)]
struct NapiModule {
    nm_version: i32,
    nm_flags: u32,
    nm_filename: *const c_char,
    nm_register_func: Option<unsafe extern "C" fn(napi_env, napi_value) -> napi_value>,
    nm_modname: *const c_char,
    nm_priv: *mut c_void,
    reserved: [*mut c_void; 4],
}

extern "C" {
    fn napi_module_register(module: *const NapiModule);
}

/// static 中的裸指针不实现 Sync，包一层并显式声明（仅注册时只读访问）。
/// cbindgen:ignore
struct SyncModule(NapiModule);
unsafe impl Sync for SyncModule {}

/// cbindgen:ignore
static MODULE: SyncModule = SyncModule(NapiModule {
    nm_version: 1,
    nm_flags: 0,
    nm_filename: ptr::null(),
    nm_register_func: Some(napi_register_module_v1),
    nm_modname: b"termirror_core\0".as_ptr() as *const c_char,
    nm_priv: ptr::null_mut(),
    reserved: [ptr::null_mut(); 4],
});

unsafe extern "C" fn register_module_ctor() {
    napi_module_register(&MODULE.0);
}

// 放进 .init_array，dlopen 时由动态链接器调用（对齐 C++ 的 __attribute__((constructor))）
/// cbindgen:ignore
#[used]
#[link_section = ".init_array"]
static REGISTER_MODULE: unsafe extern "C" fn() = register_module_ctor;
