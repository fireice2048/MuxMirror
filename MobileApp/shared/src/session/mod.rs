//! SSH 会话管理模块。
//!
//! 基于 `ssh2` crate（libssh2）。每个会话一条后台线程：
//! TCP（10s 超时）→ SSH 握手 → 密码认证 → 打开 channel →
//! request_pty(`xterm-256color`, cols/rows) → shell → 非阻塞读循环。
//!
//! - 读到的字节经 [`crate::terminal`] 处理后以 `output` 事件上报完整文本快照；
//! - `write` / `resize` / `close` 通过 mpsc 命令通道投递到会话线程，多会话并存；
//! - 连接状态以 `connectionState` 事件推进：connecting → connected / failed → closed；
//! - 事件通过全局事件 sink 分发（FFI 层注册），从后台线程发出。
//!
//! 认证：先 password，失败自动回退 keyboard-interactive（见 kbdint 模块注释）。

mod connection;

// ohos 侧 libssh2 使用 mbedtls 后端，需补齐 openssl-sys 引用的空符号（详见模块内注释）
#[cfg(target_env = "ohos")]
mod openssl_shim;

mod kbdint;

pub use connection::{check_libssh2_available, ensure_libssh2_initialized};

use serde::Deserialize;
use std::collections::HashMap;
use std::io::{Read, Write as IoWrite};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::mpsc;
use std::sync::{Mutex, OnceLock, RwLock};
use std::time::Duration;

/// 契约事件：连接状态 / 输出 / 错误 / 诊断。
#[derive(Debug, Clone, serde::Serialize)]
pub struct TmEvent {
    /// 会话 ID；诊断事件固定为 0
    #[serde(rename = "sessionId")]
    pub session_id: i64,
    /// 事件类型：connectionState / output / error / diag
    #[serde(rename = "type")]
    pub event_type: &'static str,
    /// 连接状态：connecting / connected / failed / closed
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    /// 事件数据（输出快照 / 错误信息 / 诊断结果）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<String>,
    /// 终端光标在输出快照中的 UTF-16 码元偏移（仅 output 事件携带）。
    /// 主屏模式为快照末尾；备用屏模式为真实光标位置。UI 据此插入本地输入与闪烁光标。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cursor: Option<i64>,
    /// 终端快照中的样式区间（UTF-16 码元偏移）。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub styles: Option<Vec<crate::terminal::TerminalStyleRange>>,
    /// 远端请求的鼠标输入协议：none / x10 / sgr（仅 output 事件携带）。
    #[serde(rename = "mouseProtocol", skip_serializing_if = "Option::is_none")]
    pub mouse_protocol: Option<&'static str>,
}

/// 事件 sink：由 FFI 层注册，事件从后台线程发出，需保证线程安全。
type EventSink = Box<dyn Fn(TmEvent) + Send + Sync>;

static EVENT_SINK: RwLock<Option<EventSink>> = RwLock::new(None);

/// 注册全局事件回调（覆盖旧回调）。
pub fn set_event_sink<F>(sink: F)
where
    F: Fn(TmEvent) + Send + Sync + 'static,
{
    if let Ok(mut guard) = EVENT_SINK.write() {
        *guard = Some(Box::new(sink));
    }
}

/// 分发事件到已注册的 sink；未注册时丢弃。
pub fn emit_event(event: TmEvent) {
    if let Ok(guard) = EVENT_SINK.read() {
        if let Some(sink) = guard.as_ref() {
            sink(event);
        }
    }
}

/// `tmSessionConnect` 的连接参数（契约 paramsJson）。
#[derive(Debug, Clone, Deserialize)]
pub struct ConnectParams {
    pub host: String,
    #[serde(default = "default_port")]
    pub port: u16,
    pub username: String,
    #[serde(default)]
    pub password: String,
    #[serde(default = "default_cols")]
    pub cols: u32,
    #[serde(default = "default_rows")]
    pub rows: u32,
}

fn default_port() -> u16 {
    22
}
fn default_cols() -> u32 {
    80
}
fn default_rows() -> u32 {
    24
}

/// TCP 连接超时（秒）
const CONNECT_TIMEOUT_SECS: u64 = 10;
/// 网络诊断超时（秒）
const TCP_CHECK_TIMEOUT_SECS: u64 = 5;
/// 非阻塞读循环的空转间隔（毫秒）
const IDLE_POLL_MS: u64 = 15;

/// 投递到会话线程的命令。
pub enum SessionCmd {
    /// 写入输入字节
    Write(Vec<u8>),
    /// 调整终端尺寸
    Resize(u32, u32),
    /// 关闭会话
    Close,
    /// 复用本会话的 SSH transport 执行一次性命令（新 channel，免去二次建连）。
    /// 结果经 reply 回传；会话线程未连接或已退出时 reply 不会被应答，调用方需超时回退。
    Exec {
        command: String,
        reply: mpsc::Sender<Result<String, String>>,
    },
}

/// 已认证的 SSH 会话：TCP + 握手 + 认证（不含 channel/PTY）。
///
/// 抽出此公共段供交互式 shell 会话与一次性 exec 会话复用同一套认证路径，
/// 避免密码/keyboard-interactive 回退逻辑在两处各写一份。
/// 注意：`ssh2::Session::set_tcp_stream` 会接管 TcpStream 所有权，因此这里
/// 不再单独持有 `_tcp`，会话存活期间底层 socket 由 ssh2 内部维护。
struct EstablishedSession {
    sess: ssh2::Session,
}

/// 建立 TCP + SSH 握手 + 认证，复用现有密码/keyboard-interactive 回退路径。
///
/// 返回的会话默认阻塞模式（交互式 shell 会再切非阻塞，exec 会保持阻塞）。
fn establish_connection(params: &ConnectParams) -> Result<EstablishedSession, String> {
    let t0 = std::time::Instant::now();
    // TCP（10s 超时）
    let addr = format!("{}:{}", params.host, params.port)
        .to_socket_addrs()
        .map_err(|e| format!("域名解析失败：{e}"))?
        .next()
        .ok_or_else(|| "域名解析无结果".to_string())?;
    crate::tm_i!(
        "连接计时 {}:{}：地址解析完成 {:?}",
        params.host,
        params.port,
        t0.elapsed()
    );
    let tcp = TcpStream::connect_timeout(&addr, Duration::from_secs(CONNECT_TIMEOUT_SECS))
        .map_err(|e| format!("TCP 连接失败：{e}"))?;
    crate::tm_i!(
        "连接计时 {}:{}：TCP 连接完成 {:?}",
        params.host,
        params.port,
        t0.elapsed()
    );
    // libssh2 非阻塞模式要求底层 socket 也是非阻塞的；
    // 否则 musl(OHOS) 下阻塞 fd 的 recv 行为与 darwin 不同，会报 SOCKET_RECV(-43)
    tcp.set_nonblocking(true)
        .map_err(|e| format!("设置非阻塞失败：{e}"))?;

    // SSH 握手 + 密码认证（先确保 libssh2 完整初始化，见 ensure_libssh2_initialized 注释）
    ensure_libssh2_initialized();
    let mut sess = ssh2::Session::new().map_err(|e| format!("libssh2 初始化失败：{e}"))?;
    sess.set_tcp_stream(tcp);
    sess.handshake().map_err(|e| format!("SSH 握手失败：{e}"))?;
    crate::tm_i!(
        "连接计时 {}:{}：SSH 握手完成 {:?}",
        params.host,
        params.port,
        t0.elapsed()
    );
    // 先尝试 password 认证；失败则回退 keyboard-interactive
    // （部分服务器 PAM 配置下 password 永远失败、只有 kbdint 能过，2026-07-21 真机实测）
    if let Err(e) = sess.userauth_password(&params.username, &params.password) {
        crate::tm_i!(
            "{}@{}:{} password 认证失败（{e}，耗时 {:?}），回退 keyboard-interactive",
            params.username,
            params.host,
            params.port,
            t0.elapsed()
        );
        kbdint::userauth_keyboard_interactive(&sess, &params.username, &params.password)
            .map_err(|e2| format!("认证失败：password 与 keyboard-interactive 均被拒（{e2}）"))?;
    }
    crate::tm_i!(
        "连接计时 {}:{}：认证完成 {:?}",
        params.host,
        params.port,
        t0.elapsed()
    );
    if !sess.authenticated() {
        return Err("认证失败：服务器拒绝".to_string());
    }

    Ok(EstablishedSession { sess })
}

/// 会话句柄：只保存命令通道与服务器身份（用于 exec 复用匹配），生命周期由会话线程自管理。
struct SessionHandle {
    cmd_tx: mpsc::Sender<SessionCmd>,
    host: String,
    port: u16,
    username: String,
}

static NEXT_SESSION_ID: AtomicI64 = AtomicI64::new(1);
/// exec 调用自增 ID（与 sessionId 空间隔离，避免 exec 事件被误认为某个 shell 会话事件）。
static NEXT_EXEC_ID: AtomicI64 = AtomicI64::new(1_000_000);
static SESSIONS: OnceLock<Mutex<HashMap<i64, SessionHandle>>> = OnceLock::new();

fn sessions() -> &'static Mutex<HashMap<i64, SessionHandle>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 契约 `tmSessionConnect`：同步返回 sessionId（>0），连接过程异步推进。
/// 参数解析失败返回 -1。
pub fn connect(params_json: &str) -> i64 {
    let params: ConnectParams = match serde_json::from_str(params_json) {
        Ok(p) => p,
        Err(e) => {
            crate::tm_e!("连接参数解析失败：{e}");
            emit_event(TmEvent {
                session_id: 0,
                event_type: "error",
                state: None,
                data: Some(format!("连接参数解析失败：{e}")),
                cursor: None,
                styles: None,
                mouse_protocol: None,
            });
            return -1;
        }
    };

    let session_id = NEXT_SESSION_ID.fetch_add(1, Ordering::SeqCst);
    let (cmd_tx, cmd_rx) = mpsc::channel::<SessionCmd>();
    sessions().lock().expect("会话表锁中毒").insert(
        session_id,
        SessionHandle {
            cmd_tx,
            host: params.host.clone(),
            port: params.port,
            username: params.username.clone(),
        },
    );

    let params_for_log = format!("{}@{}:{}", params.username, params.host, params.port);
    std::thread::Builder::new()
        .name(format!("termirror-session-{session_id}"))
        .spawn(move || run_session(session_id, params, cmd_rx))
        .expect("启动会话线程失败");
    crate::tm_i!("会话 {session_id} 开始连接 {params_for_log}");
    session_id
}

/// 契约 `tmSessionWrite`：向会话写入输入数据（UTF-8 字符串，可含控制字符）。
pub fn write(session_id: i64, data: &str) {
    let tx = {
        let guard = sessions().lock().expect("会话表锁中毒");
        guard.get(&session_id).map(|h| h.cmd_tx.clone())
    };
    if let Some(tx) = tx {
        let _ = tx.send(SessionCmd::Write(data.as_bytes().to_vec()));
    }
}

/// 契约 `tmSessionResize`：调整终端尺寸。
pub fn resize(session_id: i64, cols: u32, rows: u32) {
    let tx = {
        let guard = sessions().lock().expect("会话表锁中毒");
        guard.get(&session_id).map(|h| h.cmd_tx.clone())
    };
    if let Some(tx) = tx {
        let _ = tx.send(SessionCmd::Resize(cols, rows));
    }
}

/// 契约 `tmSessionClose`：关闭会话（幂等）。
pub fn close(session_id: i64) {
    let tx = {
        let guard = sessions().lock().expect("会话表锁中毒");
        guard.get(&session_id).map(|h| h.cmd_tx.clone())
    };
    if let Some(tx) = tx {
        let _ = tx.send(SessionCmd::Close);
    }
}

/// 契约 `tmSessionExec`：后台线程执行一次 SSH exec，结果经 `execResult` 事件返回。
///
/// 与 `connect` 对齐：同步返回 `execId`（>0），实际执行在后台线程中阻塞完成，
/// 成功时 `data` 携带 stdout 文本、`state`="ok"；失败时 `state`="failed"、
/// `data` 携带错误信息。`execId` 写入事件的 `sessionId` 字段以供 ArkTS 区分多次调用。
///
/// 用途：导航浮层执行 `muxmirror -format json --mux` 拉取终端窗口列表。
/// 优先复用同服务器已连接会话的 SSH transport（新开 exec channel，免二次建连）；
/// 无可用会话或复用失败时回退为独立 SSH 连接（见 [`exec_with_reuse`]）。
pub fn exec(params_json: &str, command: &str) -> i64 {
    let params: ConnectParams = match serde_json::from_str(params_json) {
        Ok(p) => p,
        Err(e) => {
            crate::tm_e!("exec 参数解析失败：{e}");
            emit_event(TmEvent {
                session_id: 0,
                event_type: "execResult",
                state: Some("failed".to_string()),
                data: Some(format!("exec 参数解析失败：{e}")),
                cursor: None,
                styles: None,
                mouse_protocol: None,
            });
            return -1;
        }
    };
    let command = command.to_string();
    let command_for_log = command.clone();
    let exec_id = NEXT_EXEC_ID.fetch_add(1, Ordering::SeqCst);
    let params_for_log = format!("{}@{}:{}", params.username, params.host, params.port);
    std::thread::Builder::new()
        .name(format!("termirror-exec-{exec_id}"))
        .spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                exec_with_reuse(exec_id, &params, &command)
            }));
            match result {
                Ok(Ok(stdout)) => {
                    crate::tm_i!("exec {exec_id} 完成（{} 字节）", stdout.len());
                    emit_event(TmEvent {
                        session_id: exec_id,
                        event_type: "execResult",
                        state: Some("ok".to_string()),
                        data: Some(stdout),
                        cursor: None,
                        styles: None,
                        mouse_protocol: None,
                    });
                }
                Ok(Err(e)) => {
                    crate::tm_e!("exec {exec_id} 失败：{e}");
                    emit_event(TmEvent {
                        session_id: exec_id,
                        event_type: "execResult",
                        state: Some("failed".to_string()),
                        data: Some(e),
                        cursor: None,
                        styles: None,
                        mouse_protocol: None,
                    });
                }
                Err(_) => {
                    crate::tm_e!("exec {exec_id} 线程 panic");
                    emit_event(TmEvent {
                        session_id: exec_id,
                        event_type: "execResult",
                        state: Some("failed".to_string()),
                        data: Some("exec 线程内部错误".to_string()),
                        cursor: None,
                        styles: None,
                        mouse_protocol: None,
                    });
                }
            }
        })
        .expect("启动 exec 线程失败");
    crate::tm_i!("exec {exec_id} 启动 {params_for_log}：{command_for_log}");
    exec_id
}

/// 查找与 params 同服务器（host/port/username 相同）的存活会话命令通道。
/// 多会话匹配时取 session_id 最大（最新）的一个。
fn find_reusable_session(params: &ConnectParams) -> Option<(i64, mpsc::Sender<SessionCmd>)> {
    let guard = sessions().lock().expect("会话表锁中毒");
    guard
        .iter()
        .filter(|(_, h)| {
            h.host == params.host && h.port == params.port && h.username == params.username
        })
        .max_by_key(|(id, _)| **id)
        .map(|(id, h)| (*id, h.cmd_tx.clone()))
}

/// exec 复用等待会话线程应答的超时（秒）。超时回退独立建连，避免会话线程卡死拖累导航页。
const EXEC_REUSE_TIMEOUT_SECS: u64 = 30;

/// exec 主体：优先复用同服务器已连接会话的 SSH transport（新开 exec channel，
/// 免二次建连——高 RTT 链路下建连占绝大部分耗时）；无存活会话、投递失败或
/// 等待超时则回退为独立 SSH 连接，保证导航页总能拿到结果。
fn exec_with_reuse(exec_id: i64, params: &ConnectParams, command: &str) -> Result<String, String> {
    if let Some((session_id, tx)) = find_reusable_session(params) {
        let (reply_tx, reply_rx) = mpsc::channel();
        if tx
            .send(SessionCmd::Exec {
                command: command.to_string(),
                reply: reply_tx,
            })
            .is_ok()
        {
            match reply_rx.recv_timeout(Duration::from_secs(EXEC_REUSE_TIMEOUT_SECS)) {
                Ok(result) => {
                    crate::tm_i!("exec {exec_id} 复用会话 {session_id} 通道");
                    return result;
                }
                Err(_) => {
                    crate::tm_w!("exec {exec_id} 等待会话 {session_id} 应答超时，回退独立建连")
                }
            }
        }
    }
    crate::tm_i!("exec {exec_id} 无可用会话，独立建连");
    exec_inner(exec_id, params, command)
}

/// exec 独立建连回退路径：建立独立 SSH 会话后执行命令。
///
/// 保持阻塞模式（exec 一次性命令很快返回，无需非阻塞轮询）。
fn exec_inner(exec_id: i64, params: &ConnectParams, command: &str) -> Result<String, String> {
    let EstablishedSession { sess } = establish_connection(params)?;
    let (out, exit_code) = exec_on_session(&sess, command)?;
    crate::tm_i!("exec {exec_id} 退出码 {exit_code}");
    Ok(out)
}

/// 在已认证的 sess（须为阻塞模式）上执行一次性命令，返回 stdout（stderr 附加于后）与退出码。
///
/// stderr 附加在 stdout 之后，前缀以换行分隔，便于诊断。命令返回码非 0 不视为失败，
/// 仅由调用方根据 stdout 内容自行判断（muxmirror 总是打印 JSON 到 stdout）。
fn exec_on_session(sess: &ssh2::Session, command: &str) -> Result<(String, i32), String> {
    let mut channel = sess
        .channel_session()
        .map_err(|e| format!("打开 exec 通道失败：{e}"))?;
    let command_with_environment = exec_command_with_environment(command);
    channel
        .exec(&command_with_environment)
        .map_err(|e| format!("exec 命令失败：{e}"))?;

    let mut stdout = Vec::new();
    let mut stderr = String::new();
    let mut buf = [0u8; 8 * 1024];
    loop {
        match channel.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => stdout.extend_from_slice(&buf[..n]),
            Err(e) => return Err(format!("exec 读取失败：{e}")),
        }
    }
    // 读取 stderr（若有）；忽略错误，stderr 非关键路径
    let mut err_buf = [0u8; 4 * 1024];
    loop {
        match channel.stderr().read(&mut err_buf) {
            Ok(0) => break,
            Ok(n) => {
                if let Ok(s) = std::str::from_utf8(&err_buf[..n]) {
                    stderr.push_str(s);
                }
            }
            Err(_) => break,
        }
    }
    channel
        .close()
        .map_err(|e| format!("exec 关闭通道失败：{e}"))?;
    let exit_code = channel
        .exit_status()
        .map_err(|e| format!("exec 取退出码失败：{e}"))?;

    let mut out = String::from_utf8_lossy(&stdout).into_owned();
    if !stderr.is_empty() {
        if !out.is_empty() && !out.ends_with('\n') {
            out.push('\n');
        }
        out.push_str(&stderr);
    }
    Ok((out, exit_code))
}

/// 为非交互 SSH exec 补齐运行环境。
///
/// exec channel 不会加载 `.zshrc` / `.bashrc`：除 PATH 缺失外，locale 也常为空。
/// tmux 在非 UTF-8 locale 下会把 `pane_current_path` 中的中文转写为下划线，导致
/// MUX 导航按目录分组时看不到原目录名，因此这里显式固定 UTF-8 locale。
fn exec_command_with_environment(command: &str) -> String {
    format!(
        "export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
         export PATH=\"/opt/homebrew/bin:/usr/local/bin:$HOME/.termimirror/bin:$PATH\"; \
         {command}"
    )
}

/// 契约 `tmTcpCheck`：后台线程 TCP 连通性诊断，结果经 diag 事件返回。
pub fn tcp_check(host: &str, port: u16) {
    let host = host.to_string();
    std::thread::Builder::new()
        .name("termirror-tcp-check".to_string())
        .spawn(move || {
            let message = match tcp_check_inner(&host, port) {
                Ok(rtt) => format!("{host}:{port} 可达，RTT ≈ {rtt:.0?}"),
                Err(e) => format!("{host}:{port} 不可达：{e}"),
            };
            crate::tm_i!("网络诊断：{message}");
            emit_event(TmEvent {
                session_id: 0,
                event_type: "diag",
                state: None,
                data: Some(message),
                cursor: None,
                styles: None,
                mouse_protocol: None,
            });
        })
        .expect("启动诊断线程失败");
}

/// 实际 TCP 连接探测，返回往返耗时。
fn tcp_check_inner(host: &str, port: u16) -> Result<Duration, String> {
    let start = std::time::Instant::now();
    let addrs = format!("{host}:{port}")
        .to_socket_addrs()
        .map_err(|e| format!("域名解析失败：{e}"))?;
    let mut last_err = String::new();
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, Duration::from_secs(TCP_CHECK_TIMEOUT_SECS)) {
            Ok(_) => return Ok(start.elapsed()),
            Err(e) => last_err = e.to_string(),
        }
    }
    Err(if last_err.is_empty() {
        "无可用地址".to_string()
    } else {
        last_err
    })
}

/// 上报连接状态事件。
fn emit_state(session_id: i64, state: &str, data: Option<String>) {
    emit_event(TmEvent {
        session_id,
        event_type: "connectionState",
        state: Some(state.to_string()),
        data,
        cursor: None,
        styles: None,
        mouse_protocol: None,
    });
}

/// 会话线程主流程。
fn run_session(session_id: i64, params: ConnectParams, cmd_rx: mpsc::Receiver<SessionCmd>) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        run_session_inner(session_id, &params, &cmd_rx)
    }));
    match result {
        Ok(Ok(())) => {
            crate::tm_i!("会话 {session_id} 已关闭");
            emit_state(session_id, "closed", None);
        }
        Ok(Err(e)) => {
            crate::tm_e!("会话 {session_id} 失败：{e}");
            emit_state(session_id, "failed", Some(e));
        }
        Err(_) => {
            crate::tm_e!("会话 {session_id} 线程 panic");
            emit_state(session_id, "failed", Some("会话线程内部错误".to_string()));
        }
    }
    sessions().lock().expect("会话表锁中毒").remove(&session_id);
}

/// 会话建立 + 读写循环（同步风格，运行在线程内）。
fn run_session_inner(
    session_id: i64,
    params: &ConnectParams,
    cmd_rx: &mpsc::Receiver<SessionCmd>,
) -> Result<(), String> {
    emit_state(session_id, "connecting", None);

    let EstablishedSession { sess } = establish_connection(params)?;

    // 打开 channel + PTY + shell
    let mut channel = sess
        .channel_session()
        .map_err(|e| format!("打开通道失败：{e}"))?;
    channel
        .request_pty(
            "xterm-256color",
            None,
            Some((params.cols, params.rows, 0, 0)),
        )
        .map_err(|e| format!("申请 PTY 失败：{e}"))?;
    channel
        .shell()
        .map_err(|e| format!("启动 shell 失败：{e}"))?;
    sess.set_blocking(false);
    crate::tm_i!(
        "会话 {session_id} 已连接 {}@{}:{}（{}x{}）",
        params.username,
        params.host,
        params.port,
        params.cols,
        params.rows
    );
    emit_state(session_id, "connected", None);

    // 非阻塞读写循环：读到的字节经终端缓冲处理后上报完整快照
    let mut terminal =
        crate::terminal::TerminalBuffer::with_size(params.cols as usize, params.rows as usize);
    let mut read_buf = [0u8; 16 * 1024];
    let mut pending_write: std::collections::VecDeque<u8> = std::collections::VecDeque::new();
    let mut closing = false;

    while !closing {
        // 处理命令队列（写 / 尺寸调整 / 关闭）
        while let Ok(cmd) = cmd_rx.try_recv() {
            match cmd {
                SessionCmd::Write(bytes) => pending_write.extend(bytes),
                SessionCmd::Resize(cols, rows) => {
                    let _ = channel.request_pty_size(cols, rows, None, None);
                    terminal.resize_size(cols as usize, rows as usize);
                }
                SessionCmd::Close => closing = true,
                SessionCmd::Exec { command, reply } => {
                    // 复用本会话 transport 执行一次性命令：临时切回阻塞模式跑完再
                    // 恢复非阻塞。执行期间 shell 输出积压在 socket 缓冲，恢复后由
                    // 下一轮循环读出；channel 仅持有 sess 的不可变借用，可共存。
                    sess.set_blocking(true);
                    let result = exec_on_session(&sess, &command).map(|(out, code)| {
                        crate::tm_i!("会话 {session_id} 复用 exec 退出码 {code}");
                        out
                    });
                    sess.set_blocking(false);
                    let _ = reply.send(result);
                }
            }
        }

        // 冲刷待发数据（非阻塞，写不动就等下一轮）
        while !pending_write.is_empty() {
            match channel.write(&pending_write.make_contiguous()) {
                Ok(n) => {
                    pending_write.drain(..n);
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(e) => return Err(format!("写入失败：{e}")),
            }
        }

        // 读取远端输出
        match channel.read(&mut read_buf) {
            Ok(0) => {
                // EOF：远端关闭
                return Ok(());
            }
            Ok(n) => {
                let snapshot = terminal.feed(&read_buf[..n]).to_string();
                let cursor = terminal.cursor_offset() as i64;
                let styles = terminal.style_ranges().to_vec();
                let mouse_protocol = terminal.mouse_protocol();
                emit_event(TmEvent {
                    session_id,
                    event_type: "output",
                    state: None,
                    data: Some(snapshot),
                    cursor: Some(cursor),
                    styles: (!styles.is_empty()).then_some(styles),
                    mouse_protocol: Some(mouse_protocol),
                });
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(IDLE_POLL_MS));
            }
            Err(e) => {
                // 直接取 libssh2 会话最后错误（ssh2 crate 转 io::Error 时丢了原始错误码）
                let (code, msg) = unsafe { last_libssh2_error(&sess) };
                let errno = unsafe { libssh2_sys::libssh2_session_last_errno(&mut *sess.raw()) };
                let errno_msg = std::io::Error::from_raw_os_error(errno).to_string();
                return Err(format!(
                    "读取失败：{e}（libssh2 [{code}] {msg}；errno={errno} {errno_msg}）"
                ));
            }
        }
    }

    let _ = channel.close();
    Ok(())
}

/// 读取 libssh2 会话的最后错误码与错误文本（用于把 io::Error 丢掉的细节找回来）。
///
/// # Safety
///
/// 调用方需保证会话仍存活；仅读取错误字符串指针，不持有。
unsafe fn last_libssh2_error(sess: &ssh2::Session) -> (i32, String) {
    use std::ffi::CStr;
    use std::os::raw::{c_char, c_int};

    let mut msg_ptr: *mut c_char = std::ptr::null_mut();
    let mut msg_len: c_int = 0;
    let code =
        libssh2_sys::libssh2_session_last_error(&mut *sess.raw(), &mut msg_ptr, &mut msg_len, 0);
    let msg = if !msg_ptr.is_null() && msg_len > 0 {
        CStr::from_ptr(msg_ptr).to_string_lossy().into_owned()
    } else {
        String::new()
    };
    (code, msg)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};

    #[test]
    fn ssh_exec命令固定utf8环境并保留原命令() {
        let wrapped = exec_command_with_environment("muxmirror -format json --mux --by-directory");

        assert!(wrapped.starts_with("export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8;"));
        assert!(wrapped.contains("$HOME/.termimirror/bin:$PATH"));
        assert!(wrapped.ends_with("muxmirror -format json --mux --by-directory"));
    }

    #[test]
    fn 事件sink可注册并收到事件() {
        // 注意：其他用例的后台会话线程也可能触发事件，这里只计数不断言内容
        static COUNT: AtomicUsize = AtomicUsize::new(0);
        let baseline = COUNT.load(AtomicOrdering::SeqCst);
        set_event_sink(move |_ev| {
            COUNT.fetch_add(1, AtomicOrdering::SeqCst);
        });
        emit_event(TmEvent {
            session_id: 0,
            event_type: "diag",
            state: None,
            data: Some("测试".to_string()),
            cursor: None,
            styles: None,
            mouse_protocol: None,
        });
        assert!(COUNT.load(AtomicOrdering::SeqCst) > baseline);
    }

    #[test]
    fn 事件序列化字段名对齐契约() {
        let event = TmEvent {
            session_id: 3,
            event_type: "connectionState",
            state: Some("connected".to_string()),
            data: None,
            cursor: None,
            styles: None,
            mouse_protocol: None,
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"sessionId\":3"));
        assert!(json.contains("\"type\":\"connectionState\""));
        assert!(json.contains("\"state\":\"connected\""));
        assert!(!json.contains("data"));
        assert!(!json.contains("cursor"));
        assert!(!json.contains("styles"));
    }

    #[test]
    fn 输出事件序列化弱化样式区间() {
        let event = TmEvent {
            session_id: 4,
            event_type: "output",
            state: None,
            data: Some("正常提示".to_string()),
            cursor: Some(4),
            styles: Some(vec![crate::terminal::TerminalStyleRange {
                start: 2,
                end: 4,
                style: "dim",
                foreground: None,
                background: None,
            }]),
            mouse_protocol: Some("sgr"),
        };
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("\"styles\":[{\"start\":2,\"end\":4,\"style\":\"dim\"}]"));
        assert!(json.contains("\"mouseProtocol\":\"sgr\""));
    }

    #[test]
    fn 非法连接参数返回负一() {
        assert_eq!(connect("不是json"), -1);
        // 合法参数：连接立即被拒绝（127.0.0.1:1 未监听），但同步分配的 sessionId 应 >0
        let id = connect(r#"{"host":"127.0.0.1","port":1,"username":"u","password":"p"}"#);
        assert!(id > 0);
        close(id);
    }

    #[test]
    fn 连接参数缺省值() {
        let params: ConnectParams = serde_json::from_str(r#"{"host":"h","username":"u"}"#).unwrap();
        assert_eq!(params.port, 22);
        assert_eq!(params.cols, 80);
        assert_eq!(params.rows, 24);
    }

    #[test]
    fn tcp诊断不可达地址返回错误() {
        // 127.0.0.1:1 几乎必然未监听，connect 应立即被拒绝
        let result = tcp_check_inner("127.0.0.1", 1);
        assert!(result.is_err());
    }

    #[test]
    fn exec非法参数返回负一() {
        // 与 connect 一致：参数 JSON 解析失败立即返回 -1，不启动后台线程
        assert_eq!(exec("不是json", "ls"), -1);
    }

    #[test]
    fn exec参数缺省值对齐connect() {
        // exec 复用 ConnectParams，缺省值应与 connect 一致（port=22）
        let params: ConnectParams = serde_json::from_str(r#"{"host":"h","username":"u"}"#).unwrap();
        assert_eq!(params.port, 22);
        assert_eq!(params.cols, 80);
        assert_eq!(params.rows, 24);
    }

    #[test]
    fn exec复用匹配同服务器最新会话() {
        let host = "reuse-test-host.invalid";
        let params = |port: u16| ConnectParams {
            host: host.to_string(),
            port,
            username: "u".to_string(),
            password: String::new(),
            cols: 80,
            rows: 24,
        };
        // 无会话时不匹配
        assert!(find_reusable_session(&params(22)).is_none());
        // 两个同服务器会话应命中 session_id 较大者；端口不同则不匹配
        let (tx1, _rx1) = mpsc::channel();
        let (tx2, _rx2) = mpsc::channel();
        {
            let mut guard = sessions().lock().expect("会话表锁中毒");
            for (id, tx) in [(1001_i64, tx1), (1002_i64, tx2)] {
                guard.insert(
                    id,
                    SessionHandle {
                        cmd_tx: tx,
                        host: host.to_string(),
                        port: 22,
                        username: "u".to_string(),
                    },
                );
            }
        }
        let (id, _) = find_reusable_session(&params(22)).expect("应匹配到会话");
        assert_eq!(id, 1002);
        assert!(find_reusable_session(&params(2222)).is_none());
        let mut guard = sessions().lock().expect("会话表锁中毒");
        guard.remove(&1001);
        guard.remove(&1002);
    }
}
