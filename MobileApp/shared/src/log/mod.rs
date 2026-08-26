//! 日志模块。
//!
//! 遵循全局日志规范：
//! - 初始化时打印 `============== App Start ==============` 与 Banner
//!   （产品名 / 版本 / 操作系统，由 `tmInit` 注入，不 hardcode 产品名到文件逻辑）；
//! - 日志文件 `<filesDir>/logs/<产品名>-YYYY-MM-DD.log`，本地 0 点滚动并复打 Banner；
//! - 级别 E/W/I/D，每行带 `[YYYY-MM-DD HH:MM:SS.mmm +08:00]` 本地时间戳；
//! - 业务线程只写内存队列（先到先得 FIFO），专用写线程落盘；
//! - 写线程把最长 2 秒内到达的日志合并成一次写盘，避免频繁 IO；
//! - 启动时清理 30 天前的日志文件。

use chrono::{Duration, NaiveDate};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::mpsc::{self, Sender};
use std::sync::OnceLock;

/// 本地时间获取。
///
/// 不能用 chrono 的 `clock` 特性（`Local::now()`）：它会拉入 iana-time-zone，
/// 该 crate 在 OHOS 上通过 `#[link(name = "time_service_ndk")]` 强链
/// libtime_service_ndk.so——NDK sysroot 里有桩库能链过，但设备（含模拟器）
/// 上没有这个库，会导致整个 libtermirror_core.so dlopen 失败、UI 降级 Mock。
/// 这里直接调 libc 的 `localtime_r` 拿本地时间与 UTC 偏移。
mod local_time {
    /// 本地时间的各字段（年/月/日/时/分/秒/毫秒/UTC 偏移秒数）。
    pub struct LocalNow {
        pub year: i32,
        pub month: u32,
        pub day: u32,
        pub hour: u32,
        pub minute: u32,
        pub second: u32,
        pub millis: u32,
        pub offset_seconds: i64,
    }

    #[cfg(unix)]
    pub fn now() -> LocalNow {
        use std::ffi::c_char;

        // libc struct tm（glibc/musl/BSD 布局一致，OHOS libc 派生自 musl）
        #[repr(C)]
        struct Tm {
            tm_sec: i32,
            tm_min: i32,
            tm_hour: i32,
            tm_mday: i32,
            tm_mon: i32,
            tm_year: i32,
            tm_wday: i32,
            tm_yday: i32,
            tm_isdst: i32,
            tm_gmtoff: i64,
            tm_zone: *const c_char,
        }

        extern "C" {
            fn localtime_r(timep: *const i64, result: *mut Tm) -> *mut Tm;
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default();
        let secs = now.as_secs() as i64;
        let mut tm = Tm {
            tm_sec: 0,
            tm_min: 0,
            tm_hour: 0,
            tm_mday: 0,
            tm_mon: 0,
            tm_year: 0,
            tm_wday: 0,
            tm_yday: 0,
            tm_isdst: 0,
            tm_gmtoff: 0,
            tm_zone: std::ptr::null(),
        };
        // SAFETY：secs 与 tm 均为有效指针；localtime_r 成功时返回 result。
        let ok = unsafe { !localtime_r(&secs, &mut tm).is_null() };
        if !ok {
            return utc_fallback(now.as_secs(), now.subsec_millis());
        }
        LocalNow {
            year: tm.tm_year + 1900,
            month: (tm.tm_mon + 1) as u32,
            day: tm.tm_mday as u32,
            hour: tm.tm_hour as u32,
            minute: tm.tm_min as u32,
            second: tm.tm_sec as u32,
            millis: now.subsec_millis(),
            offset_seconds: tm.tm_gmtoff,
        }
    }

    /// 非 unix 平台（或 localtime_r 失败时）的兜底：按 UTC 渲染。
    #[cfg(not(unix))]
    pub fn now() -> LocalNow {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default();
        utc_fallback(now.as_secs(), now.subsec_millis())
    }

    /// 由 Unix 时间戳算出 UTC 的日期时间字段（Howard Hinnant 算法）。
    fn utc_fallback(secs: u64, millis: u32) -> LocalNow {
        let days = (secs / 86400) as i64;
        let rem = secs % 86400;
        let z = days + 719468;
        let era = if z >= 0 { z } else { z - 146096 } / 146097;
        let doe = (z - era * 146097) as u64;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        let y = yoe as i64 + era * 400;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let m = if mp < 10 { mp + 3 } else { mp - 9 };
        LocalNow {
            year: if m <= 2 { y + 1 } else { y } as i32,
            month: m as u32,
            day: d as u32,
            hour: (rem / 3600) as u32,
            minute: ((rem % 3600) / 60) as u32,
            second: (rem % 60) as u32,
            millis,
            offset_seconds: 0,
        }
    }
}

/// 日志等级。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    /// 调试信息
    Debug = 1,
    /// 一般信息
    Info = 2,
    /// 可恢复异常
    Warn = 3,
    /// 操作失败
    Error = 4,
}

impl Level {
    fn tag(self) -> char {
        match self {
            Level::Debug => 'D',
            Level::Info => 'I',
            Level::Warn => 'W',
            Level::Error => 'E',
        }
    }
}

/// 一条待写日志。
struct Entry {
    line: String,
}

/// 日志器句柄：业务侧只持有发送端。
struct Logger {
    tx: Sender<Entry>,
}

static LOGGER: OnceLock<Logger> = OnceLock::new();

/// 写盘批量合并窗口（秒）
const FLUSH_WINDOW_SECS: u64 = 2;
/// 日志保留天数
const RETENTION_DAYS: i64 = 30;

/// 初始化日志系统。
///
/// - `files_dir`：应用文件目录（日志写入 `<files_dir>/logs/`）；
/// - `app_name`：产品名（用于日志文件名与 Banner，例如 `TermMirror`）；
/// - `version`：产品版本号。
///
/// 重复调用只会生效第一次（日志写线程全局唯一）。
pub fn init(files_dir: &str, app_name: &str, version: &str) {
    let logs_dir = PathBuf::from(files_dir).join("logs");
    if let Err(e) = fs::create_dir_all(&logs_dir) {
        eprintln!("[termirror_core] 创建日志目录失败：{e}");
        return;
    }
    cleanup_old_logs(&logs_dir, app_name);

    let banner = Banner {
        app_name: app_name.to_string(),
        version: version.to_string(),
    };
    let (tx, rx) = mpsc::channel::<Entry>();
    let logger = Logger { tx };
    if LOGGER.set(logger).is_err() {
        return; // 已初始化，忽略后续调用
    }
    std::thread::Builder::new()
        .name("termirror-log-writer".to_string())
        .spawn(move || writer_loop(rx, logs_dir, banner))
        .expect("启动日志写线程失败");

    info(&format!("日志系统初始化完成，目录：{}/logs", files_dir));
}

/// Banner 信息（由调用方注入，不 hardcode 产品名）。
struct Banner {
    app_name: String,
    version: String,
}

impl Banner {
    /// 生成 Banner 文本（启动与每日滚动时打印）。
    fn render(&self) -> String {
        format!(
            "============== App Start ==============\n产品: {}\n版本: {}\n系统: {} ({})\n",
            self.app_name,
            self.version,
            std::env::consts::OS,
            std::env::consts::ARCH,
        )
    }
}

/// 当前时间戳：`[YYYY-MM-DD HH:MM:SS.mmm +08:00]`（本地时区）。
fn timestamp() -> String {
    let t = local_time::now();
    let sign = if t.offset_seconds < 0 { '-' } else { '+' };
    let abs = t.offset_seconds.unsigned_abs();
    format!(
        "[{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03} {}{:02}:{:02}]",
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
        t.millis,
        sign,
        abs / 3600,
        (abs % 3600) / 60
    )
}

/// 当前本地日期。
fn today() -> NaiveDate {
    let t = local_time::now();
    NaiveDate::from_ymd_opt(t.year, t.month, t.day)
        .unwrap_or_else(|| NaiveDate::from_ymd_opt(1970, 1, 1).unwrap())
}

/// 日志文件路径：`<logs_dir>/<app>-YYYY-MM-DD.log`。
fn log_file_path(logs_dir: &std::path::Path, app_name: &str, date: NaiveDate) -> PathBuf {
    logs_dir.join(format!("{}-{}.log", app_name, date.format("%Y-%m-%d")))
}

/// 打开当日日志文件（追加模式），文件首行写 Banner。
fn open_daily_file(logs_dir: &std::path::Path, banner: &Banner, date: NaiveDate) -> Option<File> {
    let path = log_file_path(logs_dir, &banner.app_name, date);
    let need_banner = !path.exists();
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| {
            eprintln!("[termirror_core] 打开日志文件 {} 失败：{e}", path.display());
            e
        })
        .ok()?;
    if need_banner {
        let _ = file.write_all(banner.render().as_bytes());
    }
    Some(file)
}

/// 写线程主循环：按 2 秒窗口批量合并写盘，跨天滚动并复打 Banner。
fn writer_loop(rx: mpsc::Receiver<Entry>, logs_dir: PathBuf, banner: Banner) {
    let mut current_date = today();
    let mut file = open_daily_file(&logs_dir, &banner, current_date);

    loop {
        // 先阻塞等一条，再在 2 秒窗口内尽量收干队列，合并成一次写盘
        let first = match rx.recv() {
            Ok(entry) => entry,
            Err(_) => return, // 发送端全部关闭，退出写线程
        };
        let deadline =
            std::time::Instant::now() + std::time::Duration::from_secs(FLUSH_WINDOW_SECS);
        let mut batch = vec![first];
        while let Ok(entry) =
            rx.recv_timeout(deadline.saturating_duration_since(std::time::Instant::now()))
        {
            batch.push(entry);
            if deadline <= std::time::Instant::now() {
                break;
            }
        }

        // 本地 0 点滚动：日期变化时换新文件并复打 Banner
        let now = today();
        if now != current_date || file.is_none() {
            current_date = now;
            file = open_daily_file(&logs_dir, &banner, current_date);
            if let Some(f) = file.as_mut() {
                let _ = f.write_all(banner.render().as_bytes());
            }
        }

        if let Some(f) = file.as_mut() {
            let mut buf = String::new();
            for entry in &batch {
                buf.push_str(&entry.line);
                buf.push('\n');
            }
            let _ = f.write_all(buf.as_bytes());
            let _ = f.flush();
        }
    }
}

/// 启动时清理 30 天前的日志文件（按文件名中的日期解析）。
fn cleanup_old_logs(logs_dir: &std::path::Path, app_name: &str) {
    let prefix = format!("{app_name}-");
    let cutoff = today() - Duration::days(RETENTION_DAYS);
    let Ok(entries) = fs::read_dir(logs_dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        let Some(date_part) = name
            .strip_prefix(&prefix)
            .and_then(|s| s.strip_suffix(".log"))
        else {
            continue;
        };
        let Ok(date) = NaiveDate::parse_from_str(date_part, "%Y-%m-%d") else {
            continue;
        };
        if date < cutoff {
            let _ = fs::remove_file(entry.path());
        }
    }
}

/// 输出一条日志（内部实现）：格式化后投入写队列。
fn write(level: Level, message: &str) {
    let line = format!("{} [{}] {}", timestamp(), level.tag(), message);
    if let Some(logger) = LOGGER.get() {
        // 队列无界，send 不会阻塞业务线程；写线程退出后丢弃
        let _ = logger.tx.send(Entry { line });
    }
    // 未初始化时静默丢弃（tmInit 之前的日志不关键）
}

/// 输出调试级日志。
pub fn debug(message: &str) {
    write(Level::Debug, message);
}

/// 输出一般信息日志。
pub fn info(message: &str) {
    write(Level::Info, message);
}

/// 输出警告级日志。
pub fn warn(message: &str) {
    write(Level::Warn, message);
}

/// 输出错误级日志。
pub fn error(message: &str) {
    write(Level::Error, message);
}

/// 调试级日志宏：`tm_d!("消息 {}", arg)`
#[macro_export]
macro_rules! tm_d {
    ($($arg:tt)*) => { $crate::log::debug(&format!($($arg)*)) };
}

/// 一般信息日志宏：`tm_i!("消息 {}", arg)`
#[macro_export]
macro_rules! tm_i {
    ($($arg:tt)*) => { $crate::log::info(&format!($($arg)*)) };
}

/// 警告级日志宏：`tm_w!("消息 {}", arg)`
#[macro_export]
macro_rules! tm_w {
    ($($arg:tt)*) => { $crate::log::warn(&format!($($arg)*)) };
}

/// 错误级日志宏：`tm_e!("消息 {}", arg)`
#[macro_export]
macro_rules! tm_e {
    ($($arg:tt)*) => { $crate::log::error(&format!($($arg)*)) };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 时间戳格式符合规范() {
        let ts = timestamp();
        // [2026-07-20 21:40:00.123 +08:00]
        assert!(ts.starts_with('[') && ts.ends_with(']'));
        assert_eq!(ts.len(), 32);
        assert_eq!(&ts[11..12], " ");
        assert_eq!(&ts[24..25], " ");
        assert!(ts[25..].contains(|c| c == '+' || c == '-'));
    }

    #[test]
    fn banner包含产品与系统信息() {
        let banner = Banner {
            app_name: "TermMirror".to_string(),
            version: "0.1.0".to_string(),
        };
        let text = banner.render();
        assert!(text.contains("============== App Start =============="));
        assert!(text.contains("产品: TermMirror"));
        assert!(text.contains("版本: 0.1.0"));
        assert!(text.contains("系统:"));
    }

    #[test]
    fn 日志文件名按天命名() {
        let date = NaiveDate::from_ymd_opt(2026, 7, 20).unwrap();
        let path = log_file_path(std::path::Path::new("/tmp/x"), "TermMirror", date);
        assert_eq!(path.to_str().unwrap(), "/tmp/x/TermMirror-2026-07-20.log");
    }

    #[test]
    fn 清理只删过期日志文件() {
        let dir = std::env::temp_dir().join(format!("termirror_log_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let old = today() - Duration::days(31);
        let recent = today() - Duration::days(1);
        fs::write(
            dir.join(format!("TermMirror-{}.log", old.format("%Y-%m-%d"))),
            "x",
        )
        .unwrap();
        fs::write(
            dir.join(format!("TermMirror-{}.log", recent.format("%Y-%m-%d"))),
            "x",
        )
        .unwrap();
        fs::write(dir.join("其他文件.txt"), "x").unwrap();
        cleanup_old_logs(&dir, "TermMirror");
        let remaining: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(remaining.len(), 2);
        assert!(remaining
            .iter()
            .any(|n| n.contains(&recent.format("%Y-%m-%d").to_string())));
        assert!(remaining.iter().any(|n| n == "其他文件.txt"));
        let _ = fs::remove_dir_all(&dir);
    }
}
