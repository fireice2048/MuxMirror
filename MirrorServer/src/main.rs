use clap::{Parser, Subcommand};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Serialize)]
struct TabInfo {
    title: String,
    active: bool,
    mux: String,
    session: String,
    #[serde(skip)]
    ax_document: String,
}

#[derive(Serialize)]
struct WinInfo {
    #[serde(skip)]
    app: String,
    id: u32,
    pid: u32,
    title: String,
    width: u32,
    height: u32,
    tabs: Vec<TabInfo>,
}

/// CLI 参数
/// muxmirror                       # 默认树状文本输出，全部窗口+标签页
/// muxmirror --mux                 # 树状文本，仅 mux 标签页
/// muxmirror -format json          # JSON 输出全部窗口+标签页
/// muxmirror -format json --mux    # JSON 输出仅 mux 标签页
/// muxmirror -format json --mux --by-directory  # 按工作目录分组输出 mux 标签页
#[derive(Parser, Debug)]
#[command(name = "muxmirror", version, about = "MuxMirror 终端窗口枚举")]
struct Cli {
    /// 输出格式: text 或 json
    #[arg(short, long, default_value = "text")]
    format: String,
    /// 仅显示 mux (tmux/rmux) 标签页
    #[arg(long)]
    mux: bool,
    /// 按工作目录对 mux 标签页分组（建议与 --mux 一起使用）
    #[arg(long)]
    by_directory: bool,
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// 引导授予 macOS 辅助功能权限
    Setup,
    /// 检查辅助程序及 macOS 辅助功能权限
    Doctor,
}

/// 从标签页标题中检测 tmux/rmux/screen 等多路复用器
/// 标题格式: "path — user@host — short_dir — command — shell"
/// 检查 command 段是否包含 tmux/rmux/screen
fn detect_mux(title: &str) -> (String, String) {
    let segments: Vec<&str> = title.split(" — ").collect();

    // 从命令段提取 session name：创建命令使用 -s，attach/switch 使用 -t。
    // tmux 的精确目标语法允许 `-t =name`，导航目标应去掉 `=` 后再与
    // list-clients 返回的真实 session name 匹配。
    let extract_session = |s: &str| -> String {
        let parts: Vec<&str> = s.split_whitespace().collect();
        for (i, p) in parts.iter().enumerate() {
            if (*p == "-s" || *p == "-t") && i + 1 < parts.len() {
                return parts[i + 1]
                    .trim_matches(['\'', '"'])
                    .strip_prefix('=')
                    .unwrap_or(parts[i + 1].trim_matches(['\'', '"']))
                    .to_string();
            }
        }
        String::new()
    };

    let check_cmd = |s: &str| -> Option<(&'static str, String)> {
        let is_mux = if s.starts_with("tmux") || s.contains(" tmux") || s == "tmux" {
            Some("TMUX")
        } else if s.starts_with("rmux") || s.contains(" rmux") || s == "rmux" {
            Some("RMUX")
        } else if s.starts_with("screen") || s.contains(" screen") || s == "screen" {
            Some("SCREEN")
        } else {
            None
        };
        is_mux.map(|m| (m, extract_session(s)))
    };

    // 遍历所有段，找第一个匹配 mux 命令的段。
    // 标题格式可能是 "目录 — 命令 — shell — 尺寸"，但段数和顺序不固定，
    // 逐段匹配比硬编码下标更健壮。
    for seg in &segments {
        let seg_lower = seg.trim().to_lowercase();
        if let Some((mux, session)) = check_cmd(&seg_lower) {
            return (mux.to_string(), session);
        }
    }

    (String::new(), String::new())
}

// ──────────────────── macOS ────────────────────
#[cfg(target_os = "macos")]
mod platform {
    use super::*;
    use std::path::PathBuf;
    use std::process::{Command, Stdio};

    fn helper_path() -> PathBuf {
        if let Some(path) = std::env::var_os("MUXMIRROR_AX_HELPER") {
            return PathBuf::from(path);
        }
        let home = std::env::var_os("HOME").unwrap_or_default();
        // 按安装脚本的实际路径查找；.termimirror 是安装脚本的默认安装根。
        let candidate = PathBuf::from(&home)
            .join(".termimirror")
            .join("libexec")
            .join("muxmirror")
            .join("muxmirror-ax-helper");
        if candidate.is_file() {
            return candidate;
        }
        // 回退到旧路径（兼容手动安装到 .local 的场景）
        PathBuf::from(home)
            .join(".local")
            .join("libexec")
            .join("muxmirror")
            .join("muxmirror-ax-helper")
    }

    fn require_helper() -> Result<PathBuf, String> {
        let helper = helper_path();
        if helper.is_file() {
            Ok(helper)
        } else {
            Err(format!(
                "未找到 MuxMirror 辅助程序：{}\n请重新运行安装程序。",
                helper.display()
            ))
        }
    }

    fn helper_remote_command(helper: &std::path::Path, argument: &str) -> Result<String, String> {
        let helper_text = helper
            .to_str()
            .ok_or_else(|| format!("辅助程序路径不是有效 UTF-8：{}", helper.display()))?;
        let quoted_helper = format!("'{}'", helper_text.replace('\'', "'\\''"));
        if argument.is_empty() {
            Ok(quoted_helper)
        } else {
            Ok(format!("{quoted_helper} {argument}"))
        }
    }

    fn localhost_ssh_command(remote_command: &str) -> Command {
        let mut command = Command::new("/usr/bin/ssh");
        command.args([
            "-o",
            "ConnectTimeout=10",
            "-o",
            "LogLevel=ERROR",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "PreferredAuthentications=password",
            "-o",
            "PubkeyAuthentication=no",
            "-o",
            "IdentitiesOnly=yes",
            "127.0.0.1",
            remote_command,
        ]);
        command
    }

    fn localhost_ssh_guidance() -> &'static str {
        "无法通过 localhost 建立 SSH 连接。\n\
         请确认“系统设置 → 通用 → 共享 → 远程登录”已经开启，\
         并确认当前用户可以使用密码登录 localhost；若配置了 AllowUsers，\
         还需允许来源 127.0.0.1。"
    }

    fn run_helper_output(argument: &str) -> Result<std::process::Output, String> {
        let helper = require_helper()?;
        let direct = std::env::var_os("SSH_CONNECTION").is_some()
            || std::env::var("MUXMIRROR_PERMISSION_CONTEXT").as_deref() == Ok("direct");
        if direct {
            let mut command = Command::new(&helper);
            if !argument.is_empty() {
                command.arg(argument);
            }
            return command
                .output()
                .map_err(|error| format!("无法运行辅助程序 {}：{error}", helper.display()));
        }

        let remote_command = helper_remote_command(&helper, argument)?;
        // 继承终端输入，让 SSH 能读取密码；stdout/stderr 仍由 Output 捕获供调用方解析。
        localhost_ssh_command(&remote_command)
            .stdin(Stdio::inherit())
            .output()
            .map_err(|error| format!("无法通过本机 SSH 运行辅助程序：{error}"))
    }

    fn run_permission_check(prompt: bool) -> Result<bool, String> {
        let argument = if prompt {
            "--request-permission"
        } else {
            "--check-permission"
        };
        let output = run_helper_output(argument)?;

        if output.status.code() == Some(255) {
            return Err(localhost_ssh_guidance().to_string());
        }
        Ok(output.status.success())
    }

    pub fn setup_permissions() -> Result<(), String> {
        if run_permission_check(true)? {
            println!("MuxMirror 辅助功能权限已就绪。");
            return Ok(());
        }

        let _ = Command::new("/usr/bin/open")
            .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .status();
        Err(format!(
            "尚未授予辅助功能权限。\n\
             请在“系统设置 → 隐私与安全性 → 辅助功能”中允许新出现的 \
             MuxMirror/SSH 相关条目（通常是 `sshd-keygen-wrapper`）。\n\
             MuxMirror 辅助程序：{}\n\
             完成后运行 `muxmirror doctor` 验证。",
            helper_path().display()
        ))
    }

    pub fn doctor_permissions() -> Result<(), String> {
        let helper = require_helper()?;
        if run_permission_check(false)? {
            println!("辅助程序：{}", helper.display());
            println!("辅助功能权限：已授权");
            Ok(())
        } else {
            Err(format!(
                "辅助程序：{}\n辅助功能权限：未授权\n请运行 `muxmirror setup`。",
                helper.display()
            ))
        }
    }

    pub fn get_terminal_windows() -> BTreeMap<String, Vec<WinInfo>> {
        let mut apps: BTreeMap<String, Vec<WinInfo>> = BTreeMap::new();
        let output = run_helper_output("").unwrap_or_else(|error| {
            eprintln!("{error}");
            std::process::exit(2);
        });
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if output.status.code() == Some(255) {
                eprintln!("{}", localhost_ssh_guidance());
            } else if output.status.code() == Some(77)
                || stderr.contains("MUXMIRROR_PERMISSION_REQUIRED")
            {
                eprintln!("MuxMirror 尚未获得辅助功能权限；请在电脑上运行 `muxmirror setup`。");
            } else {
                eprintln!(
                    "MuxMirror 辅助程序执行失败（状态 {}）：{}",
                    output.status,
                    stderr.trim()
                );
            }
            std::process::exit(2);
        }
        let text = String::from_utf8_lossy(&output.stdout);

        for line in text.lines() {
            let parts: Vec<&str> = line.split('\x1f').collect();
            if parts.len() < 6 {
                continue;
            }
            let app = parts[0].to_string();
            let pid: u32 = parts[1].parse().unwrap_or(0);
            let title = parts[2].to_string();
            let id: u32 = parts[3].parse().unwrap_or(0);
            let w: u32 = parts[4].parse().unwrap_or(0);
            let h: u32 = parts[5].parse().unwrap_or(0);
            let mut tabs: Vec<TabInfo> = Vec::new();
            let mut i = 6;
            while i < parts.len() {
                let t = parts[i];
                let document = if i + 1 < parts.len() {
                    parts[i + 1]
                } else {
                    ""
                };
                i += 2;
                if t.is_empty() {
                    continue;
                }
                let active = t.starts_with('*');
                let title = if active {
                    t[1..].to_string()
                } else {
                    t.to_string()
                };
                let (mux, session) = detect_mux(&title);
                let doc_path = if let Some(rest) = document.strip_prefix("file://") {
                    urlencoding_decode(rest)
                } else {
                    document.to_string()
                };
                tabs.push(TabInfo {
                    title,
                    active,
                    mux,
                    session,
                    ax_document: doc_path,
                });
            }
            if title.is_empty() && (w < 100 || h < 100) {
                continue;
            }
            // 单标签页窗口没有 tab group，从窗口标题检测 mux
            if tabs.is_empty() {
                let (mux, session) = detect_mux(&title);
                if !mux.is_empty() {
                    tabs.push(TabInfo {
                        title: title.clone(),
                        active: true,
                        mux,
                        session,
                        ax_document: String::new(),
                    });
                }
            }
            apps.entry(app).or_default().push(WinInfo {
                app: String::new(),
                id,
                pid,
                title,
                width: w,
                height: h,
                tabs,
            });
        }
        apps
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::path::Path;

        #[test]
        fn quotes_helper_path_for_localhost_ssh() {
            let helper = Path::new("/tmp/Mux Mirror's/helper");
            let command =
                helper_remote_command(helper, "--check-permission").expect("valid UTF-8 path");

            assert_eq!(command, "'/tmp/Mux Mirror'\\''s/helper' --check-permission");
            assert_eq!(
                helper_remote_command(helper, "").expect("valid UTF-8 path"),
                "'/tmp/Mux Mirror'\\''s/helper'"
            );
        }

        #[test]
        fn localhost_ssh_uses_password_without_public_key_attempts() {
            let command = localhost_ssh_command("'helper' --check-permission");
            let args: Vec<String> = command
                .get_args()
                .map(|argument| argument.to_string_lossy().into_owned())
                .collect();

            assert!(args
                .windows(2)
                .any(|pair| pair == ["-o", "PreferredAuthentications=password"]));
            assert!(args
                .windows(2)
                .any(|pair| pair == ["-o", "PubkeyAuthentication=no"]));
            assert_eq!(
                args.last().map(String::as_str),
                Some("'helper' --check-permission")
            );
        }
    }
}

// ──────────────────── Windows ────────────────────
#[cfg(target_os = "windows")]
mod platform {
    use super::*;

    #[allow(non_snake_case)]
    mod win32 {
        use std::ffi::c_void;

        pub type HWND = *mut c_void;
        pub type BOOL = i32;
        pub type LPARAM = isize;
        pub type WNDENUMPROC = Option<unsafe extern "system" fn(HWND, LPARAM) -> BOOL>;

        #[repr(C)]
        pub struct RECT {
            pub left: i32,
            pub top: i32,
            pub right: i32,
            pub bottom: i32,
        }

        pub const TRUE: BOOL = 1;

        #[link(name = "user32")]
        extern "system" {
            pub fn EnumWindows(lpEnumFunc: WNDENUMPROC, lParam: LPARAM) -> BOOL;
            pub fn IsWindowVisible(hWnd: HWND) -> BOOL;
            pub fn GetWindowTextW(hWnd: HWND, lpString: *mut u16, nMaxCount: i32) -> i32;
            pub fn GetClassNameW(hWnd: HWND, lpClassName: *mut u16, nMaxCount: i32) -> i32;
            pub fn GetWindowRect(hWnd: HWND, lpRect: *mut RECT) -> BOOL;
            pub fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: *mut u32) -> u32;
        }
    }

    use win32::*;

    const TERM_CLASSES: &[&str] = &[
        "ConsoleWindowClass",
        "CASCADIA_HOSTING_WINDOW_CLASS",
        "mintty",
    ];

    struct EnumCtx {
        results: Vec<WinInfo>,
    }

    unsafe extern "system" fn enum_callback(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let ctx = &mut *(lparam as *mut EnumCtx);

        if IsWindowVisible(hwnd) != TRUE {
            return TRUE;
        }

        let mut class_buf = [0u16; 256];
        let class_len = GetClassNameW(hwnd, class_buf.as_mut_ptr(), 256);
        if class_len == 0 {
            return TRUE;
        }
        let class_name = String::from_utf16_lossy(&class_buf[..class_len as usize]);
        if !TERM_CLASSES
            .iter()
            .any(|c| c.eq_ignore_ascii_case(&class_name))
        {
            return TRUE;
        }

        let mut title_buf = [0u16; 1024];
        let title_len = GetWindowTextW(hwnd, title_buf.as_mut_ptr(), 1024);
        let title = if title_len > 0 {
            String::from_utf16_lossy(&title_buf[..title_len as usize])
        } else {
            String::new()
        };

        let mut rect = RECT {
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
        };
        GetWindowRect(hwnd, &mut rect);
        let w = (rect.right - rect.left).unsigned_abs();
        let h = (rect.bottom - rect.top).unsigned_abs();

        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);

        let id = hwnd as u32;

        ctx.results.push(WinInfo {
            app: String::new(),
            id,
            pid,
            title,
            width: w,
            height: h,
            tabs: vec![],
        });

        TRUE
    }

    pub fn get_terminal_windows() -> BTreeMap<String, Vec<WinInfo>> {
        let mut apps: BTreeMap<String, Vec<WinInfo>> = BTreeMap::new();
        let mut ctx = EnumCtx { results: vec![] };

        unsafe {
            EnumWindows(Some(enum_callback), &mut ctx as *mut EnumCtx as LPARAM);
        }

        if !ctx.results.is_empty() {
            apps.insert("Terminal".to_string(), ctx.results);
        }
        apps
    }

    pub fn setup_permissions() -> Result<(), String> {
        println!("当前平台不需要 macOS 辅助功能权限。");
        Ok(())
    }

    pub fn doctor_permissions() -> Result<(), String> {
        println!("当前平台不需要 macOS 辅助功能权限。");
        Ok(())
    }
}

// ──────────────────── Linux ────────────────────
// Linux 平台暂不支持终端窗口枚举（AX/Win32 API 不可用），
// 返回空映射；mux session 仍可通过 collect_mux_sessions 尝试
// （tmux/rmux list-clients 跨平台可用）。
#[cfg(target_os = "linux")]
mod platform {
    use super::*;

    pub fn get_terminal_windows() -> BTreeMap<String, Vec<WinInfo>> {
        BTreeMap::new()
    }

    pub fn setup_permissions() -> Result<(), String> {
        println!("当前平台不需要 macOS 辅助功能权限。");
        Ok(())
    }

    pub fn doctor_permissions() -> Result<(), String> {
        println!("当前平台不需要 macOS 辅助功能权限。");
        Ok(())
    }
}

// ──────────────────── mux session 匹配 ────────────────────

struct MuxSession {
    name: String,
    cmd: String,
    shell_cwd: String,
    attached: bool,
    mux_window_id: String,
}

/// 同一 session 的多个 attached client 只保留第一条，避免导航重复。
fn unique_mux_clients(clients: Vec<(String, String)>) -> Vec<(String, String)> {
    let mut attached_names = std::collections::HashSet::new();
    clients
        .into_iter()
        .filter(|(_, name)| attached_names.insert(name.clone()))
        .collect()
}

/// 通过 tmux/rmux list-clients 获取 attached session，并按 mux + session 去重。
/// 同一 session 可能同时被电脑、模拟器、真机等多个 client attach，导航层只应
/// 暴露一个会话；CWD 优先使用 mux 的 pane_current_path，取不到时才回退 client TTY。
fn collect_mux_sessions() -> Vec<MuxSession> {
    // 一次性获取所有进程的 tty → pid 映射
    let tty_pid_map = build_tty_pid_map();
    // 一次性获取所有 shell 进程的 pid → cwd 映射
    let pids: Vec<String> = tty_pid_map.values().cloned().collect();
    let pid_cwd_map = batch_get_cwds(&pids);

    let mut sessions = Vec::new();

    for cmd in &["tmux", "rmux"] {
        // 获取 session → (window_id, pane_current_path) 映射（用于分组匹配与目录标题）。
        let mut session_meta_map: std::collections::HashMap<String, (String, String)> =
            std::collections::HashMap::new();
        if let Ok(out) = std::process::Command::new(cmd)
            .args([
                "list-clients",
                "-F",
                "#{session_name}|#{window_id}|#{pane_current_path}",
            ])
            .output()
        {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                let parts: Vec<&str> = line.split('|').collect();
                if parts.len() >= 3 {
                    let entry = session_meta_map
                        .entry(parts[0].to_string())
                        .or_insert_with(|| (parts[1].to_string(), String::new()));
                    if entry.0.is_empty() {
                        entry.0 = parts[1].to_string();
                    }
                    if entry.1.is_empty() {
                        entry.1 = parts[2].to_string();
                    }
                }
            }
        }

        let output = std::process::Command::new(cmd)
            .args(["list-clients", "-F", "#{client_tty}|#{session_name}"])
            .output();
        let clients: Vec<(String, String)> = if let Ok(out) = output {
            String::from_utf8_lossy(&out.stdout)
                .lines()
                .filter_map(|line| {
                    let parts: Vec<&str> = line.split('|').collect();
                    if parts.len() >= 2 {
                        Some((parts[0].to_string(), parts[1].to_string()))
                    } else {
                        None
                    }
                })
                .collect()
        } else {
            continue;
        };

        for (tty, name) in unique_mux_clients(clients) {
            let tty_short = tty.strip_prefix("/dev/").unwrap_or(&tty).to_string();
            let fallback_cwd = tty_pid_map
                .get(&tty_short)
                .and_then(|pid| pid_cwd_map.get(pid))
                .cloned()
                .unwrap_or_default();
            let (win_id, pane_cwd) = session_meta_map.get(&name).cloned().unwrap_or_default();
            let cwd = if pane_cwd.is_empty() {
                fallback_cwd
            } else {
                pane_cwd
            };
            sessions.push(MuxSession {
                name,
                cmd: cmd.to_string(),
                shell_cwd: cwd,
                attached: true,
                mux_window_id: win_id,
            });
        }
    }

    // 不收集 detached session：它们是关闭标签页后的残留僵尸会话，
    // 仅 attached（有 client、正在使用）的会话才需要暴露给手机端。
    sessions
}

/// 一次性 ps 获取所有 tty → shell_pid 映射
fn build_tty_pid_map() -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    if let Ok(out) = std::process::Command::new("ps")
        .args(["-eo", "pid,tty,comm"])
        .output()
    {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 3 {
                let cmd = parts[2].strip_prefix('-').unwrap_or(parts[2]);
                if cmd == "zsh" || cmd == "bash" || cmd == "sh" {
                    map.insert(parts[1].to_string(), parts[0].to_string());
                }
            }
        }
    }
    map
}

/// 批量 lsof 获取多个进程的 CWD
fn batch_get_cwds(pids: &[String]) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    if pids.is_empty() {
        return map;
    }
    let pid_args = pids.join(",");
    if let Ok(out) = std::process::Command::new("lsof")
        .args(["-p", &pid_args, "-a", "-d", "cwd", "-Fn"])
        .env("LANG", "en_US.UTF-8")
        .env("LC_ALL", "en_US.UTF-8")
        .output()
    {
        let text = String::from_utf8_lossy(&out.stdout);
        let mut current_pid = String::new();
        for line in text.lines() {
            if let Some(pid) = line.strip_prefix('p') {
                current_pid = pid.to_string();
            } else if let Some(path) = line.strip_prefix('n') {
                if !current_pid.is_empty() {
                    map.insert(current_pid.clone(), path.to_string());
                }
            }
        }
    }
    map
}

/// 从标签页标题中提取工作目录
fn extract_dir_from_title(title: &str) -> String {
    let dir = title.split(" — ").next().unwrap_or("").trim();
    if let Some(rest) = dir.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home, rest);
        }
    }
    dir.to_string()
}

/// 解码 file:// URL：跳过主机名部分，解码百分号编码
fn urlencoding_decode(s: &str) -> String {
    // file://hostname/path → /path; file:///path → /path
    let path_part = if let Some(after_scheme) = s.strip_prefix("file://") {
        match after_scheme.find('/') {
            Some(i) => &after_scheme[i..],
            None => after_scheme,
        }
    } else {
        s
    };
    let mut result = Vec::new();
    let bytes = path_part.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) = u8::from_str_radix(&path_part[i + 1..i + 3], 16) {
                result.push(byte);
                i += 3;
                continue;
            }
        }
        result.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&result).to_string()
}

/// CWD 匹配评分：精确匹配最高，其次是路径越接近越高
fn cwd_match_score(tab_dir: &str, session_cwd: &str) -> usize {
    if tab_dir == session_cwd {
        1_000_000 // 精确匹配
    } else if session_cwd.starts_with(tab_dir) {
        session_cwd.len() + 500_000 // session 是 tab 的子目录，越深越好
    } else {
        session_cwd.len() // tab 是 session 的子目录
    }
}

/// 路径匹配：精确匹配或父子目录关系
fn path_matches(tab_dir: &str, session_cwd: &str) -> bool {
    tab_dir == session_cwd || session_cwd.starts_with(tab_dir) || tab_dir.starts_with(session_cwd)
}

/// 检查指定 mux session 的进程链是否属于指定 app PID
fn session_belongs_to_app(cmd: &str, session_name: &str, app_pid: u32) -> bool {
    // 获取该 session 的 client TTY
    let output = std::process::Command::new(cmd)
        .args(["list-clients", "-t", session_name, "-F", "#{client_tty}"])
        .output();
    let tty = if let Ok(out) = output {
        let t = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if t.is_empty() {
            return false;
        }
        t
    } else {
        return false;
    };

    let tty_short = tty.strip_prefix("/dev/").unwrap_or(&tty);

    // 获取 ps 输出，找该 TTY 上的 shell PID
    let ps_out = std::process::Command::new("ps")
        .args(["-eo", "pid,ppid,tty,comm"])
        .output();
    let ps_text = if let Ok(out) = ps_out {
        String::from_utf8_lossy(&out.stdout).to_string()
    } else {
        return false;
    };

    let mut pid_ppid: std::collections::HashMap<u32, u32> = std::collections::HashMap::new();
    let mut shell_pids: Vec<u32> = Vec::new();
    for line in ps_text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 {
            if let (Ok(pid), Ok(ppid)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                pid_ppid.insert(pid, ppid);
                if parts[2] == tty_short {
                    let comm = parts[3].strip_prefix('-').unwrap_or(parts[3]);
                    if comm == "zsh" || comm == "bash" || comm == "sh" {
                        shell_pids.push(pid);
                    }
                }
            }
        }
    }

    // 追溯 shell 进程链看是否到达 app_pid
    for shell_pid in shell_pids {
        let mut pid = shell_pid;
        for _ in 0..20 {
            if pid == app_pid {
                return true;
            }
            match pid_ppid.get(&pid) {
                Some(&ppid) if ppid > 1 => pid = ppid,
                _ => break,
            }
        }
    }

    false
}

// ──────────────────── JSON 输出结构 ────────────────────

#[derive(Serialize, Clone)]
struct TabInfoJson {
    title: String,
    active: bool,
    mux: String,
    session: String,
    cwd: String,
}

#[derive(Serialize)]
struct WinInfoJson {
    app: String,
    pid: u32,
    id: u32,
    title: String,
    width: u32,
    height: u32,
    tabs: Vec<TabInfoJson>,
}

#[derive(Serialize)]
struct DetachedJson {
    mux: String,
    session: String,
    cwd: String,
}

#[derive(Serialize)]
struct MuxListOutput {
    windows: Vec<WinInfoJson>,
    detached: Vec<DetachedJson>,
}

// ──────────────────── 通用显示逻辑 ────────────────────
fn main() {
    // 预处理 CLI 参数：将单横杠长选项（如 -format）归一化为双横杠（--format），
    // 既兼容 Go 风格 `-format json` 调用契约，又不影响 clap 对 --format / -f / --mux 的原生解析。
    let raw_args: Vec<String> = std::env::args().collect();
    let normalized_args: Vec<String> = raw_args
        .into_iter()
        .enumerate()
        .map(|(i, a)| {
            if i > 0 && a.starts_with('-') && !a.starts_with("--") && a.len() > 2 {
                format!("-{}", a)
            } else {
                a
            }
        })
        .collect();
    let cli = Cli::parse_from(normalized_args);
    if let Some(command) = cli.command {
        let result = match command {
            Commands::Setup => platform::setup_permissions(),
            Commands::Doctor => platform::doctor_permissions(),
        };
        if let Err(error) = result {
            eprintln!("{error}");
            std::process::exit(2);
        }
        return;
    }
    let mux_only = cli.mux;

    let mut apps = platform::get_terminal_windows();

    // 先收集 mux sessions（在过滤前，用于单标签页窗口检测）
    let mux_sessions = collect_mux_sessions();
    let mut used_sessions = std::collections::HashSet::new();
    let home = std::env::var("HOME").unwrap_or_default();

    // 预处理：为无标签页的窗口尝试匹配 mux session（单标签页 iTerm2 等）
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            if !win.tabs.is_empty() {
                continue;
            }
            let title_dir = extract_dir_from_title(&win.title);
            // 尝试 CWD 匹配
            let best = mux_sessions
                .iter()
                .filter(|s| {
                    s.attached
                        && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                        && !s.shell_cwd.is_empty()
                        && !title_dir.is_empty()
                        && title_dir != home
                        && path_matches(&title_dir, &s.shell_cwd)
                })
                .max_by_key(|s| cwd_match_score(&title_dir, &s.shell_cwd));
            if let Some(s) = best {
                win.tabs.push(TabInfo {
                    title: win.title.clone(),
                    active: true,
                    mux: s.cmd.to_uppercase(),
                    session: s.name.clone(),
                    ax_document: String::new(),
                });
                used_sessions.insert(format!("{}:{}", s.cmd, s.name));
            }
        }
    }

    // 第二轮预处理：通过进程链追溯，将未匹配的 mux session 分配给空标签页窗口
    for (_app_name, wins) in apps.iter_mut() {
        let empty_wins: Vec<usize> = wins
            .iter()
            .enumerate()
            .filter(|(_, w)| w.tabs.is_empty())
            .map(|(i, _)| i)
            .collect();
        if empty_wins.len() != 1 {
            continue;
        }
        let app_pid = wins
            .iter()
            .find_map(|w| if w.pid > 0 { Some(w.pid) } else { None })
            .unwrap_or(0);
        if app_pid == 0 {
            continue;
        }
        for &wi in &empty_wins {
            for s in mux_sessions.iter() {
                if !s.attached || used_sessions.contains(&format!("{}:{}", s.cmd, s.name)) {
                    continue;
                }
                if session_belongs_to_app(&s.cmd, &s.name, app_pid) {
                    let title = wins[wi].title.clone();
                    wins[wi].tabs.push(TabInfo {
                        title,
                        active: true,
                        mux: s.cmd.to_uppercase(),
                        session: s.name.clone(),
                        ax_document: String::new(),
                    });
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                    break;
                }
            }
        }
    }

    if mux_only {
        for wins in apps.values_mut() {
            for win in wins.iter_mut() {
                // --mux 模式下没有 session 的条目无法被精确定位，过滤掉避免显示 TMUX[]
                win.tabs
                    .retain(|t| !t.mux.is_empty() && !t.session.is_empty());
            }
        }
        apps.retain(|_, wins| {
            wins.retain(|w| !w.tabs.is_empty());
            !wins.is_empty()
        });
    }

    // 第一轮：通过 session name 精确匹配（标题中有 -s 参数的）
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            for tab in win.tabs.iter_mut() {
                if tab.mux.is_empty() || tab.session.is_empty() {
                    continue;
                }
                let mux_cmd = tab.mux.to_lowercase();
                let sess_lower = tab.session.to_lowercase();
                if let Some(s) = mux_sessions.iter().find(|s| {
                    s.attached
                        && s.cmd == mux_cmd
                        && s.name.to_lowercase() == sess_lower
                        && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                }) {
                    tab.session = s.name.clone();
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                }
            }
        }
    }

    // 第二轮：通过 shell CWD 匹配，优先选最长路径匹配
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            for tab in win.tabs.iter_mut() {
                if tab.mux.is_empty() || !tab.session.is_empty() {
                    continue;
                }
                let mux_cmd = tab.mux.to_lowercase();
                let title_dir = extract_dir_from_title(&tab.title);
                let doc_path = tab.ax_document.clone();
                let tab_dir = if !doc_path.is_empty() && doc_path != home {
                    doc_path
                } else if title_dir != home && !title_dir.is_empty() {
                    title_dir
                } else {
                    continue;
                };
                let best = mux_sessions
                    .iter()
                    .filter(|s| {
                        s.attached
                            && s.cmd == mux_cmd
                            && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                            && !s.shell_cwd.is_empty()
                            && path_matches(&tab_dir, &s.shell_cwd)
                    })
                    .max_by_key(|s| cwd_match_score(&tab_dir, &s.shell_cwd));
                if let Some(s) = best {
                    tab.session = s.name.clone();
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                }
            }
        }
    }

    // 第三轮：同一 iTerm 窗口内已匹配的 tab 所在的 tmux window，优先分配给同窗口的未匹配 tab
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            // 收集此 iTerm 窗口中已匹配 tab 的 tmux window ID
            let mut preferred_mux_wins: std::collections::HashSet<String> =
                std::collections::HashSet::new();
            for tab in &win.tabs {
                if !tab.session.is_empty() {
                    let mux_cmd = tab.mux.to_lowercase();
                    if let Some(s) = mux_sessions
                        .iter()
                        .find(|s| s.name == tab.session && s.cmd == mux_cmd)
                    {
                        if !s.mux_window_id.is_empty() {
                            preferred_mux_wins.insert(s.mux_window_id.clone());
                        }
                    }
                }
            }
            if preferred_mux_wins.is_empty() {
                continue;
            }
            // 未匹配的 tab 优先选择同 tmux window 的 session
            for tab in win.tabs.iter_mut() {
                if tab.mux.is_empty() || !tab.session.is_empty() {
                    continue;
                }
                let mux_cmd = tab.mux.to_lowercase();
                if let Some(s) = mux_sessions.iter().find(|s| {
                    s.attached
                        && s.cmd == mux_cmd
                        && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                        && preferred_mux_wins.contains(&s.mux_window_id)
                }) {
                    tab.session = s.name.clone();
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                }
            }
        }
    }

    // 第三轮半：通过进程链追溯，把未匹配 tab 与 tmux/rmux client 关联起来。
    // 有些标签页标题里不含 `-s 会话名`（例如 `tmux attach` 或标题被改写），
    // 但 tmux client 的进程链会指向它所在的终端 App PID，借此补全 session。
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            if win.pid == 0 {
                continue;
            }
            for tab in win.tabs.iter_mut() {
                if tab.mux.is_empty() || !tab.session.is_empty() {
                    continue;
                }
                let mux_cmd = tab.mux.to_lowercase();
                if let Some(s) = mux_sessions.iter().find(|s| {
                    s.attached
                        && s.cmd == mux_cmd
                        && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                        && session_belongs_to_app(&s.cmd, &s.name, win.pid)
                }) {
                    tab.session = s.name.clone();
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                }
            }
        }
    }

    // 第四轮：Accessibility 未能识别为标签页的 attached session，通过进程链挂到对应窗口。
    // 典型场景：tmux attach 或标题被改写后，AX 只看到一个终端窗口，但 tmux client 实际存在。
    let orphan_sessions: Vec<&MuxSession> = mux_sessions
        .iter()
        .filter(|s| s.attached && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name)))
        .collect();
    for s in orphan_sessions {
        let mut best: Option<(String, usize, usize)> = None;
        for (app_name, wins) in apps.iter() {
            for (idx, win) in wins.iter().enumerate() {
                if win.pid == 0 {
                    continue;
                }
                if !session_belongs_to_app(&s.cmd, &s.name, win.pid) {
                    continue;
                }
                // 优先挂到已有同 CWD tab 的窗口，避免多个 Terminal 窗口时乱序
                let score = win
                    .tabs
                    .iter()
                    .map(|t| {
                        let tab_dir = extract_dir_from_title(&t.title);
                        if path_matches(&tab_dir, &s.shell_cwd) {
                            1000usize
                        } else {
                            0usize
                        }
                    })
                    .max()
                    .unwrap_or(0);
                if best.as_ref().map(|(_, _, bs)| *bs < score).unwrap_or(true) {
                    best = Some((app_name.clone(), idx, score));
                }
            }
        }
        if let Some((app, idx, _)) = best {
            if let Some(win) = apps.get_mut(&app).and_then(|w| w.get_mut(idx)) {
                let title = if s.shell_cwd.is_empty() {
                    s.name.clone()
                } else {
                    abbrev_home(&s.shell_cwd, &home)
                };
                win.tabs.push(TabInfo {
                    title,
                    active: false,
                    mux: s.cmd.to_uppercase(),
                    session: s.name.clone(),
                    ax_document: String::new(),
                });
                used_sessions.insert(format!("{}:{}", s.cmd, s.name));
            }
        }
    }

    // 第五轮：剩余未匹配的，按类型顺序分配剩余 session
    for wins in apps.values_mut() {
        for win in wins.iter_mut() {
            for tab in win.tabs.iter_mut() {
                if tab.mux.is_empty() || !tab.session.is_empty() {
                    continue;
                }
                let mux_cmd = tab.mux.to_lowercase();
                if let Some(s) = mux_sessions.iter().find(|s| {
                    s.attached
                        && s.cmd == mux_cmd
                        && !used_sessions.contains(&format!("{}:{}", s.cmd, s.name))
                }) {
                    tab.session = s.name.clone();
                    used_sessions.insert(format!("{}:{}", s.cmd, s.name));
                }
            }
        }
    }

    // 把 BTreeMap 的 key（app 名）回填进每个 WinInfo.app
    for (app_name, wins) in apps.iter_mut() {
        for win in wins.iter_mut() {
            win.app = app_name.clone();
        }
    }

    if cli.format == "json" {
        print_json(&apps, &mux_sessions, mux_only, cli.by_directory);
    } else {
        print_text(&apps, &mux_sessions, mux_only, cli.by_directory);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_setup_subcommand() {
        let cli = Cli::try_parse_from(["muxmirror", "setup"]).expect("setup 应可解析");
        assert!(matches!(cli.command, Some(Commands::Setup)));
    }

    #[test]
    fn parses_doctor_subcommand() {
        let cli = Cli::try_parse_from(["muxmirror", "doctor"]).expect("doctor 应可解析");
        assert!(matches!(cli.command, Some(Commands::Doctor)));
    }

    #[test]
    fn detects_exact_tmux_attach_target_from_terminal_title() {
        let title = "~/Repo/TermHook — tmux attach-session -t =tab-14 — 120×30";

        assert_eq!(
            detect_mux(title),
            ("TMUX".to_string(), "tab-14".to_string())
        );
    }

    #[test]
    fn detects_quoted_rmux_switch_target_from_terminal_title() {
        let title = "~/Repo/TermHook — rmux switch-client -t '=team' — zsh";

        assert_eq!(detect_mux(title), ("RMUX".to_string(), "team".to_string()));
    }

    #[test]
    fn mux_session_identity_ignores_client_count() {
        let clients = vec![
            ("/dev/ttys000".to_string(), "tab-14".to_string()),
            ("/dev/ttys006".to_string(), "tab-14".to_string()),
            ("/dev/ttys012".to_string(), "tab-14".to_string()),
            ("/dev/ttys004".to_string(), "tab-13".to_string()),
        ];

        let unique = unique_mux_clients(clients);

        assert_eq!(unique.len(), 2);
        assert_eq!(unique[0].1, "tab-14");
        assert_eq!(unique[1].1, "tab-13");
    }
}

/// 将家目录前缀缩写为 ~（与终端标题习惯一致）
fn abbrev_home(path: &str, home: &str) -> String {
    if !home.is_empty() && path.starts_with(home) {
        let rest = &path[home.len()..];
        if rest.is_empty() {
            "~".to_string()
        } else if rest.starts_with('/') {
            format!("~{}", rest)
        } else {
            path.to_string()
        }
    } else {
        path.to_string()
    }
}

/// JSON 输出
fn print_json(
    apps: &BTreeMap<String, Vec<WinInfo>>,
    mux_sessions: &[MuxSession],
    mux_only: bool,
    by_directory: bool,
) {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut windows: Vec<WinInfoJson> = Vec::new();
    let mut used_sessions: std::collections::HashSet<String> = std::collections::HashSet::new();
    for wins in apps.values() {
        for win in wins {
            let tabs: Vec<TabInfoJson> = win
                .tabs
                .iter()
                .map(|t| {
                    // 当前路径优先级：AXDocument > 标题提取的目录 > mux session 的 shell CWD
                    let title_dir = extract_dir_from_title(&t.title);
                    let title_dir_ok =
                        !title_dir.is_empty() && title_dir != home && title_dir.starts_with('/');
                    let cwd = if !t.ax_document.is_empty() && t.ax_document != home {
                        t.ax_document.clone()
                    } else if title_dir_ok {
                        title_dir
                    } else if !t.session.is_empty() {
                        let mux_cmd = t.mux.to_lowercase();
                        mux_sessions
                            .iter()
                            .find(|s| s.cmd == mux_cmd && s.name == t.session)
                            .map(|s| s.shell_cwd.clone())
                            .unwrap_or_default()
                    } else {
                        String::new()
                    };
                    // 家目录前缀缩写为 ~（与终端标题习惯一致）
                    let cwd = abbrev_home(&cwd, &home);
                    if !t.mux.is_empty() && !t.session.is_empty() {
                        used_sessions.insert(format!("{}:{}", t.mux.to_lowercase(), t.session));
                    }
                    TabInfoJson {
                        title: t.title.clone(),
                        active: t.active,
                        mux: t.mux.clone(),
                        session: t.session.clone(),
                        cwd,
                    }
                })
                .collect();
            // --mux 模式下 tabs 已在前面 retain 过非空 mux，这里再保险过滤
            let tabs = if mux_only {
                tabs.into_iter().filter(|t| !t.mux.is_empty()).collect()
            } else {
                tabs
            };
            if mux_only && tabs.is_empty() {
                continue;
            }
            windows.push(WinInfoJson {
                app: win.app.clone(),
                pid: win.pid,
                id: win.id,
                title: win.title.clone(),
                width: win.width,
                height: win.height,
                tabs,
            });
        }
    }

    // 补充：Accessibility 未能识别到的 attached tmux/rmux session（例如窗口标题
    // 不含 tmux 命令、或权限/路径匹配失败），仍以独立窗口列出，避免手机上找不到。
    for s in mux_sessions.iter().filter(|s| s.attached) {
        let key = format!("{}:{}", s.cmd, s.name);
        if used_sessions.contains(&key) {
            continue;
        }
        let mux_upper = s.cmd.to_uppercase();
        let cwd = abbrev_home(&s.shell_cwd, &home);
        windows.push(WinInfoJson {
            app: String::new(),
            pid: 0,
            id: 0,
            title: if cwd.is_empty() {
                "未匹配到终端窗口".to_string()
            } else {
                cwd.clone()
            },
            width: 0,
            height: 0,
            tabs: vec![TabInfoJson {
                title: s.name.clone(),
                active: true,
                mux: mux_upper,
                session: s.name.clone(),
                cwd: cwd.clone(),
            }],
        });
    }

    let detached: Vec<DetachedJson> = mux_sessions
        .iter()
        .filter(|s| !s.attached)
        .map(|s| DetachedJson {
            mux: s.cmd.to_uppercase(),
            session: s.name.clone(),
            cwd: abbrev_home(&s.shell_cwd, &home),
        })
        .collect();

    if by_directory {
        let mut groups: BTreeMap<String, Vec<TabInfoJson>> = BTreeMap::new();
        for win in &windows {
            for tab in &win.tabs {
                if tab.mux.is_empty() || tab.session.is_empty() {
                    continue;
                }
                let key = if tab.cwd.is_empty() {
                    tab.session.clone()
                } else {
                    tab.cwd.clone()
                };
                groups.entry(key).or_default().push(tab.clone());
            }
        }
        windows = groups
            .into_iter()
            .map(|(key, tabs)| WinInfoJson {
                app: String::new(),
                pid: 0,
                id: 0,
                title: key,
                width: 0,
                height: 0,
                tabs,
            })
            .collect();
    }

    let output = MuxListOutput { windows, detached };
    match serde_json::to_string_pretty(&output) {
        Ok(s) => println!("{}", s),
        Err(e) => eprintln!("JSON 序列化失败: {}", e),
    }
}

/// 计算标签页的当前工作目录，优先级与 JSON 输出保持一致。
fn tab_cwd(tab: &TabInfo, mux_sessions: &[MuxSession], home: &str) -> String {
    let title_dir = extract_dir_from_title(&tab.title);
    let title_dir_ok = !title_dir.is_empty() && title_dir != home && title_dir.starts_with('/');
    let cwd = if !tab.ax_document.is_empty() && tab.ax_document != home {
        tab.ax_document.clone()
    } else if title_dir_ok {
        title_dir
    } else if !tab.session.is_empty() {
        let mux_cmd = tab.mux.to_lowercase();
        mux_sessions
            .iter()
            .find(|s| s.cmd == mux_cmd && s.name == tab.session)
            .map(|s| s.shell_cwd.clone())
            .unwrap_or_default()
    } else {
        String::new()
    };
    abbrev_home(&cwd, home)
}

/// 树状文本输出
fn print_text(
    apps: &BTreeMap<String, Vec<WinInfo>>,
    mux_sessions: &[MuxSession],
    mux_only: bool,
    by_directory: bool,
) {
    // Linux 平台 apps 为空时给出提示
    if apps.is_empty() && cfg!(target_os = "linux") {
        println!("Linux 平台暂不支持终端窗口枚举");
        // detached 仍尝试输出
        let detached: Vec<&MuxSession> = mux_sessions.iter().filter(|s| !s.attached).collect();
        if !detached.is_empty() {
            println!("\nDetached sessions:");
            for s in &detached {
                let cwd = if s.shell_cwd.is_empty() {
                    String::new()
                } else {
                    format!(" ({})", s.shell_cwd)
                };
                println!("  {} [{}]{}", s.cmd.to_uppercase(), s.name, cwd);
            }
        }
        return;
    }

    println!("Scanning terminal windows...\n");

    let home = std::env::var("HOME").unwrap_or_default();

    // --by-directory：以 cwd 为维度聚合 mux 标签页，顶层不再显示窗口结构。
    if by_directory {
        let mut groups: BTreeMap<String, Vec<&TabInfo>> = BTreeMap::new();
        let mut total_tabs = 0usize;
        for wins in apps.values() {
            for win in wins {
                for tab in &win.tabs {
                    if tab.mux.is_empty() || tab.session.is_empty() {
                        continue;
                    }
                    total_tabs += 1;
                    let cwd = tab_cwd(tab, mux_sessions, &home);
                    let key = if cwd.is_empty() {
                        tab.session.clone()
                    } else {
                        cwd
                    };
                    groups.entry(key).or_default().push(tab);
                }
            }
        }

        println!(
            "按目录分组 ({} 个目录, {} 个标签页)\n",
            groups.len(),
            total_tabs
        );

        let group_count = groups.len();
        for (idx, (dir, tabs)) in groups.iter().enumerate() {
            let last_group = idx == group_count - 1;
            let prefix = if last_group { "└──" } else { "├──" };
            println!("{} {} [{} tabs]", prefix, dir, tabs.len());
            let pipe = if last_group { "    " } else { "│   " };
            for (ti, tab) in tabs.iter().enumerate() {
                let is_last = ti == tabs.len() - 1;
                let tab_sub = if is_last { "└──" } else { "├──" };
                let marker = if tab.active { " *" } else { "" };
                let mux_badge = format!("[{}][{}]", tab.mux, tab.session);
                let tab_t = if tab.title.is_empty() {
                    "(no title)"
                } else {
                    &tab.title
                };
                println!(
                    "{}{}[{}]{} {}{}",
                    pipe, tab_sub, ti, mux_badge, tab_t, marker
                );
            }
        }

        // 显示 detached（未连接）的 mux session
        let detached: Vec<&MuxSession> = mux_sessions.iter().filter(|s| !s.attached).collect();
        if !detached.is_empty() {
            println!("\nDetached sessions:");
            for s in &detached {
                let cwd = if s.shell_cwd.is_empty() {
                    String::new()
                } else {
                    format!(" ({})", s.shell_cwd)
                };
                println!("  {} [{}]{}", s.cmd.to_uppercase(), s.name, cwd);
            }
        }
        return;
    }

    let mut total_windows = 0usize;
    let mut total_tabs = 0usize;
    for wins in apps.values() {
        total_windows += wins.len();
        for w in wins {
            // mux_only: 统计全部 tab；否则只统计多标签页窗口的 tab。
            // 两个分支累加表达式相同，合并为单一条件。
            if mux_only || w.tabs.len() > 1 {
                total_tabs += w.tabs.len();
            }
        }
    }

    if total_tabs > 0 {
        println!(
            "Terminal: {} window{}, {} tab{}\n",
            total_windows,
            if total_windows != 1 { "s" } else { "" },
            total_tabs,
            if total_tabs != 1 { "s" } else { "" }
        );
    } else {
        println!(
            "Terminal: {} window{}\n",
            total_windows,
            if total_windows != 1 { "s" } else { "" }
        );
    }

    let app_count = apps.len();
    for (idx, (app, wins)) in apps.iter().enumerate() {
        let last_app = idx == app_count - 1;
        let prefix = if last_app { "└──" } else { "├──" };
        let total_tabs_app: usize = if mux_only {
            wins.iter().map(|w| w.tabs.len()).sum()
        } else {
            wins.iter()
                .filter(|w| w.tabs.len() > 1)
                .map(|w| w.tabs.len())
                .sum()
        };
        let extra = if total_tabs_app > 0 {
            format!(", {} tabs", total_tabs_app)
        } else {
            String::new()
        };
        println!(
            "{} {} ({} window{}{})",
            prefix,
            app,
            wins.len(),
            if wins.len() != 1 { "s" } else { "" },
            extra
        );

        let pipe = if last_app { "    " } else { "│   " };
        let win_count = wins.len();
        for (wi, win) in wins.iter().enumerate() {
            let sub = if wi == win_count - 1 {
                "└──"
            } else {
                "├──"
            };
            let id_s = format!(" [WinID:{} PID:{}]", win.id, win.pid);
            let size_s = format!(" ({}x{})", win.width, win.height);
            let t = if win.title.is_empty() {
                "(no title)".to_string()
            } else {
                win.title.clone()
            };
            let show_tabs = if mux_only {
                !win.tabs.is_empty()
            } else {
                win.tabs.len() > 1
            };
            let tab_badge = if show_tabs {
                format!(" [{} tabs]", win.tabs.len())
            } else {
                String::new()
            };
            println!("{}{} {}{}{}{}", pipe, sub, t, id_s, size_s, tab_badge);

            if show_tabs {
                let inner_pipe = if last_app { "    " } else { "│   " };
                let win_inner = if wi == win_count - 1 {
                    "    "
                } else {
                    "│   "
                };
                for (ti, tab) in win.tabs.iter().enumerate() {
                    let is_last = ti == win.tabs.len() - 1;
                    let tab_sub = if is_last { "└──" } else { "├──" };
                    let marker = if tab.active { " *" } else { "" };
                    let mux_badge = if !tab.mux.is_empty() {
                        let sess = if !tab.session.is_empty() {
                            format!("][{}", tab.session)
                        } else {
                            String::new()
                        };
                        format!("[{}{}]", tab.mux, sess)
                    } else {
                        String::new()
                    };
                    let tab_t = if tab.title.is_empty() {
                        "(no title)"
                    } else {
                        &tab.title
                    };
                    println!(
                        "{}{}{}[{}]{} {}{}",
                        inner_pipe, win_inner, tab_sub, ti, mux_badge, tab_t, marker
                    );
                }
            }
        }
    }

    // 显示 detached（未连接）的 mux session
    let detached: Vec<&MuxSession> = mux_sessions.iter().filter(|s| !s.attached).collect();
    if !detached.is_empty() {
        println!("\nDetached sessions:");
        for s in &detached {
            let cwd = if s.shell_cwd.is_empty() {
                String::new()
            } else {
                format!(" ({})", s.shell_cwd)
            };
            println!("  {} [{}]{}", s.cmd.to_uppercase(), s.name, cwd);
        }
    }
}
