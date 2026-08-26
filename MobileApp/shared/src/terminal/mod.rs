//! 终端输出处理模块：ANSI 转义序列剥离与 `\r` 覆盖语义。
//!
//! 行为对齐原 Kotlin 实现（`stripAnsiEscapeWithBuffer` 与
//! `appendTerminalOutput`，KMP 方案已删除），用 Rust 重写：
//! - 增量接收 SSH 通道字节流，按 UTF-8 边界切分，不完整多字节序列缓存到下一块；
//! - 剥离 ANSI 转义序列（CSI / OSC / 字符集选择）与杂散控制字符，
//!   末尾不完整的转义序列缓存等待下一块数据；
//! - 维护当前完整文本快照：行内 `\r` 覆盖当前行，块尾 `\r` 延迟判定；
//! - 快照超过上限时截断保留尾部，防止无限增长。

use std::collections::VecDeque;

/// 文本快照上限（字节），超出后截断保留尾部（契约约定 256KB）
const MAX_SNAPSHOT_BYTES: usize = 256 * 1024;

/// 备用屏网格默认行数（与 PTY 请求的 rows 不一致时以 with_rows 为准）
const DEFAULT_ALT_ROWS: usize = 24;
const DEFAULT_ALT_COLS: usize = 80;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalStyleRange {
    pub start: usize,
    pub end: usize,
    pub style: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub foreground: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background: Option<String>,
}

/// 终端输出缓冲：增量喂入字节，产出处理后的完整文本快照。
///
/// 双屏模型（对齐真实终端）：
/// - **主屏**：普通 shell 的线性文本快照，保留滚动回看与 `\r` 覆盖语义；
/// - **备用屏**：tmux / vim / less 等全屏 TUI 经 `ESC[?1049h` 进入，用二维网格
///   表示"当前画面"，光标定位/清屏/滚动指令在原位重绘，快照即当前屏内容，
///   不会随重绘累积增长。退出备用屏（`ESC[?1049l`）回到主屏。
#[derive(Default)]
pub struct TerminalBuffer {
    /// 主屏线性滚动回看（保留逐字符 ANSI 样式）。
    main: MainScreen,
    /// 备用屏网格；None 表示当前处于主屏
    alt: Option<AltScreen>,
    /// 当前对外快照（主屏或备用屏渲染结果）
    view: String,
    /// 当前快照中终端光标的 UTF-16 码元偏移（与 ArkTS substring 索引对齐）。
    /// 主屏模式恒等于 view 的末尾；备用屏模式为光标 (cur_r, cur_c) 在渲染文本中的位置。
    view_cursor: usize,
    /// 当前快照中的弱化文字区间（UTF-16 偏移）。
    view_styles: Vec<TerminalStyleRange>,
    /// 读块边界处不完整的 UTF-8 多字节序列
    pending_utf8: Vec<u8>,
    /// 读块边界处不完整的 ANSI 转义序列
    pending_escape: String,
    /// 备用屏网格行数
    alt_rows: usize,
    /// 备用屏网格列数
    alt_cols: usize,
    /// DEC 鼠标跟踪模式位：1000/1002/1003 可独立启停。
    mouse_tracking_modes: u8,
    /// 是否启用 SGR 扩展鼠标坐标编码（DECSET 1006）。
    mouse_sgr: bool,
}

impl TerminalBuffer {
    /// 创建空缓冲（备用屏默认 24 行）。
    pub fn new() -> Self {
        Self::with_rows(DEFAULT_ALT_ROWS)
    }

    /// 创建空缓冲并指定备用屏行数（应与 PTY 请求的 rows 一致）。
    pub fn with_rows(rows: usize) -> Self {
        Self::with_size(DEFAULT_ALT_COLS, rows)
    }

    /// 创建空缓冲并指定备用屏列数和行数（应与 PTY 请求一致）。
    pub fn with_size(cols: usize, rows: usize) -> Self {
        Self {
            alt_rows: rows.max(1),
            alt_cols: cols.max(1),
            ..Self::default()
        }
    }

    /// PTY 尺寸变化时更新备用屏行数；网格在场则同步调整。
    /// 列宽无需处理（行内 char 列表不定长，渲染时自然省略右侧空白）。
    pub fn resize(&mut self, rows: usize) {
        self.resize_size(self.alt_cols, rows);
    }

    /// PTY 尺寸变化时同步更新备用屏列数和行数。
    pub fn resize_size(&mut self, cols: usize, rows: usize) {
        self.alt_cols = cols.max(1);
        self.alt_rows = rows.max(1);
        if let Some(alt) = self.alt.as_mut() {
            alt.resize(self.alt_cols, self.alt_rows);
            self.rebuild_view();
        }
    }

    /// 喂入一段通道字节，返回处理后的完整文本快照。
    pub fn feed(&mut self, bytes: &[u8]) -> &str {
        self.pending_utf8.extend_from_slice(bytes);
        // 只处理完整 UTF-8 前缀，尾部不完整多字节序列留待下一块
        let valid_len = valid_utf8_prefix_len(&self.pending_utf8);
        let chunk = String::from_utf8_lossy(&self.pending_utf8[..valid_len]).into_owned();
        self.pending_utf8.drain(..valid_len);

        let input = format!("{}{chunk}", self.pending_escape);
        let (toks, pending) = tokenize(&input);
        self.pending_escape = pending;

        for tok in &toks {
            self.apply_mouse_mode(tok);
            if self.alt.is_none() && is_alt_enter(tok) {
                // 主屏 token 已逐个落地；切换到独立备用屏网格。
                self.alt = Some(AltScreen::new(self.alt_cols, self.alt_rows));
                continue;
            }
            if self.alt.is_some() && is_alt_exit(tok) {
                // 退出备用屏：回到主屏（主屏快照一直保留，自然恢复）
                self.alt = None;
                continue;
            }
            match self.alt {
                None => self.main.apply(tok),
                Some(ref mut alt) => alt.apply(tok),
            }
        }
        self.main.truncate_tail(MAX_SNAPSHOT_BYTES);
        self.rebuild_view();
        &self.view
    }

    /// 重算对外快照与光标偏移（主屏末尾 / 备用屏光标坐标）。
    fn rebuild_view(&mut self) {
        match &self.alt {
            None => {
                let (snapshot, styles) = self.main.snapshot_with_styles();
                self.view = snapshot;
                self.view_cursor = utf16_len(&self.view);
                self.view_styles = styles;
            }
            Some(alt) => {
                let (snap, cursor, styles) = alt.snapshot_with_cursor();
                self.view = snap;
                self.view_cursor = cursor;
                self.view_styles = styles;
            }
        }
    }

    /// 当前完整文本快照。
    pub fn snapshot(&self) -> &str {
        &self.view
    }

    /// 当前快照中终端光标的 UTF-16 码元偏移（供 UI 在该处插入本地输入与闪烁光标）。
    /// 主屏模式恒为快照末尾；备用屏模式为光标在渲染文本中的真实位置。
    pub fn cursor_offset(&self) -> usize {
        self.view_cursor
    }

    /// 当前快照中的弱化文字区间（UTF-16 偏移）。
    pub fn style_ranges(&self) -> &[TerminalStyleRange] {
        &self.view_styles
    }

    /// 远端当前请求的鼠标输入协议。没有跟踪请求时返回 `none`，防止普通 Shell
    /// 收到鼠标转义序列；1006 开启时优先使用无坐标上限的 SGR 编码。
    pub fn mouse_protocol(&self) -> &'static str {
        if self.mouse_tracking_modes == 0 {
            "none"
        } else if self.mouse_sgr {
            "sgr"
        } else {
            "x10"
        }
    }

    fn apply_mouse_mode(&mut self, tok: &Tok) {
        let Tok::Csi { params, final_byte } = tok else {
            return;
        };
        let enabled = match final_byte {
            'h' => true,
            'l' => false,
            _ => return,
        };
        let Some(body) = params.strip_prefix('?') else {
            return;
        };
        for part in body.split(';') {
            let tracking_bit = match part {
                "1000" => Some(1),
                "1002" => Some(2),
                "1003" => Some(4),
                _ => None,
            };
            if let Some(bit) = tracking_bit {
                if enabled {
                    self.mouse_tracking_modes |= bit;
                } else {
                    self.mouse_tracking_modes &= !bit;
                }
            } else if part == "1006" {
                self.mouse_sgr = enabled;
            }
        }
    }
}

/// 字符串的 UTF-16 码元长度（与 ArkTS `String.substring` 索引对齐）。
fn utf16_len(s: &str) -> usize {
    s.chars().map(|c| c.len_utf16()).sum()
}

/// 返回字节切片中完整 UTF-8 前缀的长度（尾部不完整多字节序列不计入）。
fn valid_utf8_prefix_len(bytes: &[u8]) -> usize {
    match std::str::from_utf8(bytes) {
        Ok(_) => bytes.len(),
        // error_len 为 None 表示结尾是截断的多字节序列，valid_up_to 即完整前缀长度
        Err(e) => e.valid_up_to() + e.error_len().unwrap_or(0),
    }
}

/// 判断是否为「其他控制字符」（对齐 Kotlin 的 OTHER_CONTROL_REGEX）。
/// 保留退格(0x08)、`\t`(0x09)、`\n`(0x0A)、`\r`(0x0D)；注意 ESC(0x1B) 也在剥离范围内，
/// 未构成合法转义序列的孤立 ESC 会被丢弃。
fn is_other_control(byte: u8) -> bool {
    matches!(byte, 0x00..=0x07 | 0x0B | 0x0C | 0x0E..=0x1F | 0x7F)
}

/// 转义序列分词结果。
#[derive(Debug, Clone, PartialEq, Eq)]
enum Tok {
    /// 可见文本（保留 `\t`/`\n`/`\r`，已剔除其他杂散控制字符）
    Text(String),
    /// CSI 序列 `ESC [ <params> <final>`；params 含参数字节(0x30-0x3F)与中间字节(0x20-0x2F)。
    Csi { params: String, final_byte: char },
    /// 双字符转义 `ESC <c>`（如 `ESC =` / `ESC >` / `ESC 7` / `ESC 8` / `ESC c` / `ESC D` / `ESC M`）。
    Esc2(char),
    // OSC 序列（标题/超链接等）整体消费、不产出 token。
}

/// 增量分词：把输入切成文本与转义序列 token。
///
/// 返回 `(tokens, 末尾不完整转义序列)`；后者由调用方缓存并与下一块数据拼接后再处理。
/// 这是 [`strip_ansi_escape`] 的通用化版本：剥离器只取 Text token，网格渲染器则
/// 解释 Csi/Esc2 token 的光标与清除语义。
fn tokenize(input: &str) -> (Vec<Tok>, String) {
    let bytes = input.as_bytes();
    let len = bytes.len();
    let mut toks: Vec<Tok> = Vec::new();
    let mut text: Vec<u8> = Vec::with_capacity(len);
    let mut i = 0;

    while i < len {
        if bytes[i] != 0x1B {
            if !is_other_control(bytes[i]) {
                text.push(bytes[i]);
            }
            i += 1;
            continue;
        }
        // ESC：先落地已累积的可见文本
        if !text.is_empty() {
            toks.push(Tok::Text(String::from_utf8_lossy(&text).into_owned()));
            text.clear();
        }
        if i + 1 >= len {
            // 末尾孤立 ESC，缓存等待下一块
            return (toks, input[i..].to_string());
        }
        match bytes[i + 1] {
            b'[' => {
                // CSI：参数区 0x30-0x3F + 中间字节 0x20-0x2F + 终结字节 0x40-0x7E
                let mut j = i + 2;
                while j < len && (0x30..=0x3F).contains(&bytes[j]) {
                    j += 1;
                }
                while j < len && (0x20..=0x2F).contains(&bytes[j]) {
                    j += 1;
                }
                if j >= len {
                    // 不完整 CSI，缓存
                    return (toks, input[i..].to_string());
                }
                if (0x40..=0x7E).contains(&bytes[j]) {
                    // params 区均为 ASCII，切片安全
                    toks.push(Tok::Csi {
                        params: input[i + 2..j].to_string(),
                        final_byte: bytes[j] as char,
                    });
                }
                // 非法终结：同样消费到 j+1，避免泄漏可打印字符（与剥离器行为一致）
                i = j + 1;
            }
            b']' => {
                // OSC：直到 BEL 或 ESC \ 结束
                let mut j = i + 2;
                let mut terminated = false;
                while j < len {
                    if bytes[j] == 0x07 {
                        j += 1;
                        terminated = true;
                        break;
                    }
                    if bytes[j] == 0x1B && j + 1 < len && bytes[j + 1] == b'\\' {
                        j += 2;
                        terminated = true;
                        break;
                    }
                    j += 1;
                }
                if !terminated {
                    // 不完整 OSC，缓存
                    return (toks, input[i..].to_string());
                }
                i = j; // OSC 整体丢弃
            }
            b'(' | b')' => {
                // 字符集选择：ESC ( X / ESC ) X
                if i + 2 >= len {
                    return (toks, input[i..].to_string());
                }
                if matches!(bytes[i + 2], b'A' | b'B' | b'0') {
                    i += 3;
                } else {
                    i += 1; // 非法字符集序列：丢弃 ESC
                }
            }
            _ => {
                // 双字符转义序列（ESC = / ESC > / ESC 7 / ESC 8 / ESC c / ESC D / ESC M 等）
                toks.push(Tok::Esc2(bytes[i + 1] as char));
                i += 2;
            }
        }
    }
    if !text.is_empty() {
        toks.push(Tok::Text(String::from_utf8_lossy(&text).into_owned()));
    }
    (toks, String::new())
}

/// 判断 token 是否为「进入备用屏」：`ESC[?1049h` / `ESC[?1047h` / `ESC[?47h`。
fn is_alt_enter(tok: &Tok) -> bool {
    matches!(tok, Tok::Csi { params, final_byte: 'h' } if is_alt_mode(params))
}

/// 判断 token 是否为「退出备用屏」：`ESC[?1049l` / `ESC[?1047l` / `ESC[?47l`。
fn is_alt_exit(tok: &Tok) -> bool {
    matches!(tok, Tok::Csi { params, final_byte: 'l' } if is_alt_mode(params))
}

/// 参数是否为备用屏私有模式号（1049 / 1047 / 47），允许与其他模式号同列（`;` 分隔）。
fn is_alt_mode(params: &str) -> bool {
    let body = params.strip_prefix('?').unwrap_or("");
    body.split(';')
        .any(|part| matches!(part, "1049" | "1047" | "47"))
}

/// 剥离 ANSI 转义序列与杂散控制字符。
///
/// 返回 `(可见文本, 末尾不完整转义序列)`；后者由调用方缓存并与下一块数据拼接后再处理。
/// 主屏（线性快照）路径使用；备用屏路径直接用 [`tokenize`] 解释光标语义。
pub fn strip_ansi_escape(input: &str) -> (String, String) {
    let (toks, pending) = tokenize(input);
    let mut out = String::new();
    for tok in &toks {
        if let Tok::Text(s) = tok {
            out.push_str(s);
        }
    }
    (out, pending)
}

/// 追加终端输出并实现 `\r` 覆盖语义（对齐 Kotlin `appendTerminalOutput`）：
/// - 行内 `\r`（非 `\r\n`）丢弃当前行已显示内容（zsh 行尾标记、进度条依赖该行为）；
/// - 连续 `\r` 合并为一个，不删除内容；
/// - 块尾 `\r` 延迟到下一块判定，避免把跨块的 `\r\n` 误判为行内回车。
pub fn append_terminal_output(current: &str, incoming: &str) -> String {
    let mut buffer = current.to_string();
    let text = incoming.as_bytes();

    if buffer.ends_with('\r') {
        if incoming.starts_with('\n') {
            // CRLF 被拆块：正常追加
        } else if incoming.starts_with('\r') {
            buffer.pop(); // 连续 \r：合并为一个
        } else if !incoming.is_empty() {
            // 跨块的“\r + 可见字符”：覆盖当前行
            buffer.pop();
            let keep = buffer.rfind('\n').map(|p| p + 1).unwrap_or(0);
            buffer.truncate(keep);
        }
    }

    let mut line_start = buffer.rfind('\n').map(|p| p + 1).unwrap_or(0);
    let mut i = 0;
    while i < text.len() {
        match text[i] {
            b'\x08' if i + 2 < text.len() && text[i + 1] == b' ' && text[i + 2] == b'\x08' => {
                // shell 回显退格的常见序列：BS + 空格覆盖 + BS。线性主屏直接删掉前一字符。
                if buffer.len() > line_start {
                    let previous = buffer
                        .char_indices()
                        .next_back()
                        .map(|(index, _)| index)
                        .unwrap_or(line_start);
                    if previous >= line_start {
                        buffer.truncate(previous);
                    }
                }
                i += 3;
            }
            b'\x08' => {
                // 少数终端只回显 BS；主屏没有独立光标模型，按可见效果删除前一字符。
                if buffer.len() > line_start {
                    let previous = buffer
                        .char_indices()
                        .next_back()
                        .map(|(index, _)| index)
                        .unwrap_or(line_start);
                    if previous >= line_start {
                        buffer.truncate(previous);
                    }
                }
                i += 1;
            }
            b'\r' if i + 1 < text.len() && text[i + 1] == b'\n' => {
                buffer.push_str("\r\n");
                line_start = buffer.len();
                i += 2;
            }
            b'\r' if i + 1 < text.len() && text[i + 1] == b'\r' => {
                // 连续 \r：真实终端无删除效果，丢弃前者
                i += 1;
            }
            b'\r' if i + 1 == text.len() => {
                buffer.push('\r'); // 块尾 \r：延迟判定
                i += 1;
            }
            b'\r' => {
                buffer.truncate(line_start); // 行内 \r：覆盖当前行
                i += 1;
            }
            byte => {
                // 逐字节追加需保持 UTF-8 完整：先计算该 char 的字节数
                let ch_len = utf8_len(byte);
                let end = (i + ch_len).min(text.len());
                // incoming 来自合法 UTF-8 字符串，切片必在边界上
                buffer.push_str(&incoming[i..end]);
                if byte == b'\n' {
                    line_start = buffer.len();
                }
                i = end;
            }
        }
    }
    buffer
}

/// 由 UTF-8 首字节推断该 char 的字节长度。
fn utf8_len(first: u8) -> usize {
    match first {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        _ => 4,
    }
}

/// 备用屏（alternate screen）二维网格模型。
///
/// tmux / vim / less 等全屏 TUI 经 `ESC[?1049h` 进入备用屏，用光标定位 +
/// 清屏/清行/滚动在**原位重绘**固定画面。线性快照无法表达"原地覆盖"，
/// 需要一个行列表格：可打印字符写到光标处并右移光标，CSI 光标/清除/滚动
/// 指令改变网格状态，快照即当前网格按行拼接（去掉行尾空白与尾部空行）。
#[derive(Clone, Copy)]
struct Cell {
    ch: char,
    bold: bool,
    dim: bool,
    /// 反色显示（SGR 7）：前景/背景互换，tmux 状态栏依赖该样式。
    inverse: bool,
    foreground: Option<TerminalColor>,
    background: Option<TerminalColor>,
    /// 宽字符（CJK 全角等显示宽度为 2）的延续占位格：
    /// 前一个 cell 是真正字符，本 cell 仅占列、渲染为空。
    wide_pad: bool,
}

impl Cell {
    const fn blank() -> Self {
        Self {
            ch: ' ',
            bold: false,
            dim: false,
            inverse: false,
            foreground: None,
            background: None,
            wide_pad: false,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct TerminalColor(u8, u8, u8);

impl TerminalColor {
    fn css(self) -> String {
        format!("#{:02X}{:02X}{:02X}", self.0, self.1, self.2)
    }

    fn indexed(index: usize) -> Self {
        const ANSI: [TerminalColor; 16] = [
            TerminalColor(0x00, 0x00, 0x00),
            TerminalColor(0xCD, 0x31, 0x31),
            TerminalColor(0x0D, 0xAC, 0x59),
            TerminalColor(0xE5, 0xE5, 0x10),
            TerminalColor(0x24, 0x73, 0xC8),
            TerminalColor(0xBC, 0x3F, 0xBC),
            TerminalColor(0x11, 0xA8, 0xCD),
            TerminalColor(0xE5, 0xE5, 0xE5),
            TerminalColor(0x66, 0x66, 0x66),
            TerminalColor(0xF1, 0x4C, 0x4C),
            TerminalColor(0x23, 0xD1, 0x8B),
            TerminalColor(0xF5, 0xF5, 0x43),
            TerminalColor(0x3B, 0x8E, 0xEA),
            TerminalColor(0xD6, 0x70, 0xD6),
            TerminalColor(0x29, 0xB8, 0xDB),
            TerminalColor(0xFF, 0xFF, 0xFF),
        ];
        match index {
            0..=15 => ANSI[index],
            16..=231 => {
                let value = index - 16;
                let component = |n: usize| -> u8 {
                    if n == 0 {
                        0
                    } else {
                        (55 + n * 40) as u8
                    }
                };
                TerminalColor(
                    component(value / 36),
                    component((value / 6) % 6),
                    component(value % 6),
                )
            }
            232..=255 => {
                let gray = (8 + (index - 232) * 10) as u8;
                TerminalColor(gray, gray, gray)
            }
            _ => ANSI[15],
        }
    }
}

/// 更新一组 SGR 状态。主屏与备用屏共用同一实现，确保两种屏幕的颜色语义一致。
fn apply_sgr_state(
    params: &str,
    bold: &mut bool,
    faint: &mut bool,
    gray: &mut bool,
    inverse: &mut bool,
    foreground: &mut Option<TerminalColor>,
    background: &mut Option<TerminalColor>,
) {
    let codes = if params.is_empty() {
        vec![0]
    } else {
        params
            .split(';')
            .map(|part| part.parse::<usize>().unwrap_or(0))
            .collect()
    };
    let mut index = 0;
    while index < codes.len() {
        let code = codes[index];
        match code {
            0 => {
                *bold = false;
                *faint = false;
                *gray = false;
                *inverse = false;
                *foreground = None;
                *background = None;
            }
            1 => *bold = true,
            2 => *faint = true,
            22 => {
                *bold = false;
                *faint = false;
            }
            7 => *inverse = true,
            27 => *inverse = false,
            30..=37 => {
                *gray = false;
                *foreground = Some(TerminalColor::indexed(code - 30));
            }
            39 => {
                *gray = false;
                *foreground = None;
            }
            40..=47 => *background = Some(TerminalColor::indexed(code - 40)),
            49 => *background = None,
            90..=97 => {
                *gray = code == 90;
                *foreground = Some(TerminalColor::indexed(code - 90 + 8));
            }
            100..=107 => {
                *background = Some(TerminalColor::indexed(code - 100 + 8));
            }
            38 | 48 => {
                let target_foreground = code == 38;
                let color = match codes.get(index + 1).copied() {
                    Some(5) if index + 2 < codes.len() => {
                        index += 2;
                        Some(TerminalColor::indexed(codes[index].min(255)))
                    }
                    Some(2) if index + 4 < codes.len() => {
                        let color = TerminalColor(
                            codes[index + 2].min(255) as u8,
                            codes[index + 3].min(255) as u8,
                            codes[index + 4].min(255) as u8,
                        );
                        index += 4;
                        Some(color)
                    }
                    _ => None,
                };
                if target_foreground {
                    *gray = false;
                    *foreground = color;
                } else {
                    *background = color;
                }
            }
            _ => {}
        }
        index += 1;
    }
}

#[derive(Clone, Copy)]
struct MainCell {
    ch: char,
    bold: bool,
    dim: bool,
    inverse: bool,
    foreground: Option<TerminalColor>,
    background: Option<TerminalColor>,
}

/// 普通 shell 主屏：保持线性滚动历史，同时为每个可见字符保存写入时的 SGR 状态。
#[derive(Default)]
struct MainScreen {
    cells: Vec<MainCell>,
    bold: bool,
    faint: bool,
    gray: bool,
    inverse: bool,
    foreground: Option<TerminalColor>,
    background: Option<TerminalColor>,
}

impl MainScreen {
    fn apply(&mut self, tok: &Tok) {
        match tok {
            Tok::Text(text) => self.append_text(text),
            Tok::Csi {
                params,
                final_byte: 'm',
            } => apply_sgr_state(
                params,
                &mut self.bold,
                &mut self.faint,
                &mut self.gray,
                &mut self.inverse,
                &mut self.foreground,
                &mut self.background,
            ),
            // RIS 至少复位样式；主屏仍沿用既有线性历史，不在这里清空滚动内容。
            Tok::Esc2('c') => apply_sgr_state(
                "0",
                &mut self.bold,
                &mut self.faint,
                &mut self.gray,
                &mut self.inverse,
                &mut self.foreground,
                &mut self.background,
            ),
            _ => {}
        }
    }

    fn append_text(&mut self, incoming: &str) {
        let chars: Vec<char> = incoming.chars().collect();

        if self.cells.last().is_some_and(|cell| cell.ch == '\r') {
            match chars.first().copied() {
                Some('\n') => {}
                Some('\r') => {
                    self.cells.pop();
                }
                Some(_) => {
                    self.cells.pop();
                    let keep = self
                        .cells
                        .iter()
                        .rposition(|cell| cell.ch == '\n')
                        .map(|position| position + 1)
                        .unwrap_or(0);
                    self.cells.truncate(keep);
                }
                None => {}
            }
        }

        let mut line_start = self
            .cells
            .iter()
            .rposition(|cell| cell.ch == '\n')
            .map(|position| position + 1)
            .unwrap_or(0);
        let mut index = 0;
        while index < chars.len() {
            match chars[index] {
                '\x08'
                    if index + 2 < chars.len()
                        && chars[index + 1] == ' '
                        && chars[index + 2] == '\x08' =>
                {
                    if self.cells.len() > line_start {
                        self.cells.pop();
                    }
                    index += 3;
                }
                '\x08' => {
                    if self.cells.len() > line_start {
                        self.cells.pop();
                    }
                    index += 1;
                }
                '\r' if index + 1 < chars.len() && chars[index + 1] == '\n' => {
                    self.push_char('\r');
                    self.push_char('\n');
                    line_start = self.cells.len();
                    index += 2;
                }
                '\r' if index + 1 < chars.len() && chars[index + 1] == '\r' => {
                    index += 1;
                }
                '\r' if index + 1 == chars.len() => {
                    self.push_char('\r');
                    index += 1;
                }
                '\r' => {
                    self.cells.truncate(line_start);
                    index += 1;
                }
                ch => {
                    self.push_char(ch);
                    if ch == '\n' {
                        line_start = self.cells.len();
                    }
                    index += 1;
                }
            }
        }
    }

    fn push_char(&mut self, ch: char) {
        let visible = !matches!(ch, '\r' | '\n' | '\t');
        self.cells.push(MainCell {
            ch,
            bold: visible && self.bold,
            dim: visible && (self.faint || self.gray),
            inverse: visible && self.inverse,
            foreground: visible.then_some(self.foreground).flatten(),
            background: visible.then_some(self.background).flatten(),
        });
    }

    fn truncate_tail(&mut self, max_bytes: usize) {
        let total_bytes: usize = self.cells.iter().map(|cell| cell.ch.len_utf8()).sum();
        if total_bytes <= max_bytes {
            return;
        }
        let mut removed_bytes = 0;
        let mut remove_count = 0;
        while total_bytes - removed_bytes > max_bytes && remove_count < self.cells.len() {
            removed_bytes += self.cells[remove_count].ch.len_utf8();
            remove_count += 1;
        }
        self.cells.drain(..remove_count);
    }

    fn snapshot_with_styles(&self) -> (String, Vec<TerminalStyleRange>) {
        let mut text = String::new();
        let mut offset = 0;
        let mut styles = Vec::new();
        for cell in &self.cells {
            let start = offset;
            text.push(cell.ch);
            offset += cell.ch.len_utf16();
            let style = if cell.inverse {
                "inverse"
            } else if cell.dim {
                "dim"
            } else if cell.bold {
                "bold"
            } else {
                "normal"
            };
            if style != "normal" || cell.foreground.is_some() || cell.background.is_some() {
                append_style_range(
                    &mut styles,
                    start,
                    offset,
                    style,
                    cell.foreground.map(TerminalColor::css),
                    cell.background.map(TerminalColor::css),
                );
            }
        }
        (text, styles)
    }
}

struct AltScreen {
    /// 网格行，每行一个单元格列表（允许不等长，渲染时右侧空白自然省略）
    rows: Vec<Vec<Cell>>,
    /// 全屏上滚移出的历史行（按快照上限淘汰最旧内容）。
    history: VecDeque<Vec<Cell>>,
    history_bytes: usize,
    n_cols: usize,
    n_rows: usize,
    /// 光标位置（0 起）
    cur_r: usize,
    cur_c: usize,
    wrap_pending: bool,
    /// 滚动区域（0 起，闭区间）
    scroll_top: usize,
    scroll_bottom: usize,
    /// DECSC（ESC 7）保存的光标
    saved: Option<(usize, usize)>,
    bold: bool,
    faint: bool,
    gray: bool,
    /// 反色显示状态（SGR 7 开启 / SGR 27 关闭）
    inverse: bool,
    foreground: Option<TerminalColor>,
    background: Option<TerminalColor>,
}

impl AltScreen {
    fn new(n_cols: usize, n_rows: usize) -> Self {
        let n_cols = n_cols.max(1);
        let n_rows = n_rows.max(1);
        Self {
            rows: vec![Vec::new(); n_rows],
            history: VecDeque::new(),
            history_bytes: 0,
            n_cols,
            n_rows,
            cur_r: 0,
            cur_c: 0,
            wrap_pending: false,
            scroll_top: 0,
            scroll_bottom: n_rows - 1,
            saved: None,
            bold: false,
            faint: false,
            gray: false,
            inverse: false,
            foreground: None,
            background: None,
        }
    }

    /// 调整网格列数和行数（PTY resize 时调用）。扩行补空、缩行截断，
    /// 并收敛光标与滚动区域，避免越界。重绘随后由 TUI 全屏刷新补齐。
    fn resize(&mut self, n_cols: usize, n_rows: usize) {
        let n_cols = n_cols.max(1);
        let n_rows = n_rows.max(1);
        if n_cols == self.n_cols && n_rows == self.n_rows {
            return;
        }
        for row in &mut self.rows {
            row.truncate(n_cols);
        }
        for row in &mut self.history {
            row.truncate(n_cols);
        }
        self.rows.resize(n_rows, Vec::new());
        self.n_cols = n_cols;
        self.n_rows = n_rows;
        if self.cur_r >= n_rows {
            self.cur_r = n_rows - 1;
        }
        self.cur_c = self.cur_c.min(n_cols - 1);
        self.wrap_pending = false;
        if self.scroll_top >= n_rows {
            self.scroll_top = 0;
        }
        if self.scroll_bottom >= n_rows {
            self.scroll_bottom = n_rows - 1;
        }
        if let Some((r, c)) = self.saved {
            if r >= n_rows {
                self.saved = Some((n_rows - 1, c));
            }
        }
    }

    /// 把 token 应用到网格。
    fn apply(&mut self, tok: &Tok) {
        match tok {
            Tok::Text(s) => {
                for ch in s.chars() {
                    match ch {
                        '\r' => {
                            self.cur_c = 0;
                            self.wrap_pending = false;
                        }
                        '\n' => {
                            self.line_feed();
                            self.wrap_pending = false;
                        }
                        '\t' => {
                            self.cur_c = (((self.cur_c / 8) + 1) * 8).min(self.n_cols - 1);
                            self.wrap_pending = false;
                        }
                        '\x08' => {
                            self.cur_c = self.cur_c.saturating_sub(1);
                            self.wrap_pending = false;
                        }
                        c => self.put_char(c),
                    }
                }
            }
            Tok::Csi { params, final_byte } => self.csi(params, *final_byte),
            Tok::Esc2(c) => self.esc2(*c),
        }
    }

    /// 在光标处写入字符并右移光标（超出行宽自动补空格）。
    ///
    /// 列宽与远端 PTY 的 wcwidth 规则对齐：显示宽度为 2 的字符（CJK 全角）
    /// 占两个 cell——本 cell 存字符，紧跟一个 `wide_pad` 占位 cell 补列；
    /// 覆盖写入时顺带抹掉相邻的半宽残留，避免新旧内容错位。
    fn put_char(&mut self, ch: char) {
        use unicode_width::UnicodeWidthChar;
        let width = ch.width().unwrap_or(0);
        if width == 0 {
            // 组合字符/控制字符不占列；极简模型直接丢弃
            return;
        }
        if self.wrap_pending || self.cur_c + width > self.n_cols {
            self.cur_c = 0;
            self.line_feed();
            self.wrap_pending = false;
        }
        if self.cur_r >= self.n_rows || self.cur_c >= self.n_cols {
            return;
        }
        let row = &mut self.rows[self.cur_r];
        let need = self.cur_c + width;
        if row.len() < need {
            row.resize(need, Cell::blank());
        }
        // 覆盖在宽字符的占位格上时，抹掉左侧残存的半个宽字符
        if row[self.cur_c].wide_pad && self.cur_c > 0 {
            row[self.cur_c - 1] = Cell::blank();
        }
        // 覆盖宽字符主体时，抹掉右侧残存的占位格
        if width == 1 && self.cur_c + 1 < row.len() && row[self.cur_c + 1].wide_pad {
            row[self.cur_c + 1] = Cell::blank();
        }
        let cell = Cell {
            ch,
            bold: self.bold,
            dim: self.faint || self.gray,
            inverse: self.inverse,
            foreground: self.foreground,
            background: self.background,
            wide_pad: false,
        };
        row[self.cur_c] = cell;
        if width == 2 {
            // 宽字符吃掉下一个 cell：若下个 cell 原本是宽字符主体，其右侧占位也要清掉
            if self.cur_c + 2 < row.len() && row[self.cur_c + 2].wide_pad {
                row[self.cur_c + 2] = Cell::blank();
            }
            row[self.cur_c + 1] = Cell {
                wide_pad: true,
                ..cell
            };
        }
        self.cur_c += width;
        if self.cur_c >= self.n_cols {
            self.cur_c = self.n_cols - 1;
            self.wrap_pending = true;
        }
    }

    /// 换行（LF）：光标下移一行；已在滚动区域底部则上滚一行。
    fn line_feed(&mut self) {
        if self.cur_r == self.scroll_bottom {
            self.scroll_up(1);
        } else if self.cur_r + 1 < self.n_rows {
            self.cur_r += 1;
        }
    }

    /// 滚动区域内整体上移 n 行，底部补空行。
    fn scroll_up(&mut self, n: usize) {
        let top = self.scroll_top;
        let bottom = self.scroll_bottom.min(self.n_rows.saturating_sub(1));
        if top > bottom {
            return;
        }
        let n = n.min(bottom - top + 1);
        for _ in 0..n {
            let removed = self.rows.remove(top);
            if top == 0 && bottom + 1 == self.n_rows {
                self.push_history(removed);
            }
            self.rows.insert(bottom, Vec::new());
        }
    }

    fn push_history(&mut self, row: Vec<Cell>) {
        self.history_bytes += row.iter().map(|cell| cell.ch.len_utf8()).sum::<usize>() + 1;
        self.history.push_back(row);
        while self.history_bytes > MAX_SNAPSHOT_BYTES {
            let Some(oldest) = self.history.pop_front() else {
                break;
            };
            self.history_bytes = self
                .history_bytes
                .saturating_sub(oldest.iter().map(|cell| cell.ch.len_utf8()).sum::<usize>() + 1);
        }
    }

    /// 滚动区域内整体下移 n 行，顶部补空行。
    fn scroll_down(&mut self, n: usize) {
        let top = self.scroll_top;
        let bottom = self.scroll_bottom.min(self.n_rows.saturating_sub(1));
        if top > bottom {
            return;
        }
        let n = n.min(bottom - top + 1);
        for _ in 0..n {
            self.rows.remove(bottom);
            self.rows.insert(top, Vec::new());
        }
    }

    /// `ESC[K`：清除光标到行尾。
    fn clear_eol(&mut self) {
        if self.cur_r < self.n_rows {
            let row = &mut self.rows[self.cur_r];
            if self.cur_c < row.len() {
                row.truncate(self.cur_c);
            }
        }
    }

    /// `ESC[1K`：清除行首到光标（含光标处）。
    fn clear_bol(&mut self) {
        if self.cur_r < self.n_rows {
            let row = &mut self.rows[self.cur_r];
            let upto = (self.cur_c + 1).min(row.len());
            for cell in row.iter_mut().take(upto) {
                *cell = Cell::blank();
            }
        }
    }

    /// `ESC[2K`：清除整行。
    fn clear_line(&mut self) {
        if self.cur_r < self.n_rows {
            self.rows[self.cur_r].clear();
        }
    }

    /// `ESC[J`：清除光标以下（含当前行光标右侧）。
    fn clear_below(&mut self) {
        self.clear_eol();
        for r in (self.cur_r + 1)..self.n_rows {
            self.rows[r].clear();
        }
    }

    /// `ESC[1J`：清除光标以上（含当前行光标左侧）。
    fn clear_above(&mut self) {
        for r in 0..self.cur_r.min(self.n_rows) {
            self.rows[r].clear();
        }
        self.clear_bol();
    }

    /// `ESC[2J` / `ESC[3J`：清除整屏。
    fn clear_all(&mut self) {
        for row in self.rows.iter_mut() {
            row.clear();
        }
    }

    /// `ESC[<n>X`（ECH）：擦除光标起 n 个字符（置空白，光标不动）。
    /// tmux 重绘裁剪行尾时大量使用（如 split-window 后抹掉右侧残留）。
    fn erase_chars(&mut self, n: usize) {
        if self.cur_r < self.n_rows {
            let row = &mut self.rows[self.cur_r];
            if self.cur_c < row.len() {
                let end = (self.cur_c + n).min(row.len());
                for cell in row.iter_mut().take(end).skip(self.cur_c) {
                    *cell = Cell::blank();
                }
            }
        }
    }

    /// `ESC[<n>P`（DCH）：删除光标起 n 个字符，右侧内容左移补齐。
    fn delete_chars(&mut self, n: usize) {
        if self.cur_r < self.n_rows {
            let row = &mut self.rows[self.cur_r];
            if self.cur_c < row.len() {
                let end = (self.cur_c + n).min(row.len());
                row.drain(self.cur_c..end);
            }
        }
    }

    /// `ESC[<n>@`（ICH）：光标处插入 n 个空白字符，右侧内容右移（超出列宽截断）。
    fn insert_chars(&mut self, n: usize) {
        if self.cur_r < self.n_rows {
            let n = n.min(self.n_cols.saturating_sub(self.cur_c));
            let at = self.cur_c.min(self.rows[self.cur_r].len());
            let row = &mut self.rows[self.cur_r];
            for _ in 0..n {
                row.insert(at, Cell::blank());
            }
            row.truncate(self.n_cols);
        }
    }

    /// `ESC[<n>L`（IL）：滚动区域内光标行处插入 n 个空行，底部行被挤出。
    fn insert_lines(&mut self, n: usize) {
        let bottom = self.scroll_bottom.min(self.n_rows.saturating_sub(1));
        if self.cur_r < self.scroll_top || self.cur_r > bottom {
            return;
        }
        for _ in 0..n.min(bottom - self.cur_r + 1) {
            self.rows.remove(bottom);
            self.rows.insert(self.cur_r, Vec::new());
        }
    }

    /// `ESC[<n>M`（DL）：滚动区域内删除光标行起 n 行，底部补空行。
    fn delete_lines(&mut self, n: usize) {
        let bottom = self.scroll_bottom.min(self.n_rows.saturating_sub(1));
        if self.cur_r < self.scroll_top || self.cur_r > bottom {
            return;
        }
        for _ in 0..n.min(bottom - self.cur_r + 1) {
            self.rows.remove(self.cur_r);
            self.rows.insert(bottom, Vec::new());
        }
    }

    /// 解释 CSI 序列。
    fn csi(&mut self, params: &str, final_byte: char) {
        // 参数字节均为 ASCII；提取数字（忽略 ? > = 等私有前缀），按 ; 分割
        let nums: Vec<usize> = params
            .split(|c: char| !c.is_ascii_digit())
            .filter(|p| !p.is_empty())
            .map(|p| p.parse::<usize>().unwrap_or(0))
            .collect();
        let n1 = nums.first().copied().unwrap_or(0);
        let n2 = nums.get(1).copied().unwrap_or(0);
        // 光标定位类指令参数 0 等价于 1
        let r1 = n1.max(1);
        let c1 = n2.max(1);
        if final_byte != 'm' {
            self.wrap_pending = false;
        }

        match final_byte {
            'H' | 'f' => {
                self.cur_r = (r1 - 1).min(self.n_rows.saturating_sub(1));
                self.cur_c = (c1 - 1).min(self.n_cols - 1);
            }
            'A' => self.cur_r = self.cur_r.saturating_sub(n1.max(1)),
            'B' => self.cur_r = (self.cur_r + n1.max(1)).min(self.n_rows.saturating_sub(1)),
            'C' => self.cur_c = (self.cur_c + n1.max(1)).min(self.n_cols - 1),
            'D' => self.cur_c = self.cur_c.saturating_sub(n1.max(1)),
            'G' => self.cur_c = (r1 - 1).min(self.n_cols - 1),
            'd' => self.cur_r = (r1 - 1).min(self.n_rows.saturating_sub(1)),
            's' => self.saved = Some((self.cur_r, self.cur_c)),
            'u' => {
                if let Some((r, c)) = self.saved {
                    self.cur_r = r;
                    self.cur_c = c;
                }
            }
            'J' => match n1 {
                0 => self.clear_below(),
                1 => self.clear_above(),
                _ => self.clear_all(),
            },
            'K' => match n1 {
                0 => self.clear_eol(),
                1 => self.clear_bol(),
                _ => self.clear_line(),
            },
            'r' => {
                // 滚动区域（1 起，含两端）
                self.scroll_top = (r1 - 1).min(self.n_rows.saturating_sub(1));
                self.scroll_bottom = (c1 - 1).min(self.n_rows.saturating_sub(1));
                self.cur_r = 0;
                self.cur_c = 0;
            }
            'S' => self.scroll_up(n1.max(1)),
            'T' => self.scroll_down(n1.max(1)),
            'X' => self.erase_chars(n1.max(1)),
            'P' => self.delete_chars(n1.max(1)),
            '@' => self.insert_chars(n1.max(1)),
            'L' => self.insert_lines(n1.max(1)),
            'M' => self.delete_lines(n1.max(1)),
            'm' => self.sgr(params),
            // 光标显隐(?25)、鼠标、备用屏(?1049 由 TerminalBuffer 处理)等忽略
            _ => {}
        }
    }

    fn sgr(&mut self, params: &str) {
        apply_sgr_state(
            params,
            &mut self.bold,
            &mut self.faint,
            &mut self.gray,
            &mut self.inverse,
            &mut self.foreground,
            &mut self.background,
        );
    }

    /// 解释双字符转义。
    fn esc2(&mut self, c: char) {
        match c {
            '7' => self.saved = Some((self.cur_r, self.cur_c)), // DECSC
            '8' => {
                // DECRC
                if let Some((r, c)) = self.saved {
                    self.cur_r = r;
                    self.cur_c = c;
                }
            }
            'D' => self.line_feed(), // IND：下移/上滚
            'M' => {
                // RI：上移/下滚
                if self.cur_r == self.scroll_top {
                    self.scroll_down(1);
                } else {
                    self.cur_r = self.cur_r.saturating_sub(1);
                }
            }
            'c' => {
                // RIS：整屏复位
                self.clear_all();
                self.cur_r = 0;
                self.cur_c = 0;
                self.scroll_top = 0;
                self.scroll_bottom = self.n_rows.saturating_sub(1);
                self.bold = false;
                self.faint = false;
                self.gray = false;
                self.inverse = false;
                self.foreground = None;
                self.background = None;
            }
            _ => {}
        }
    }

    /// 渲染当前网格并返回终端光标在渲染文本中的 UTF-16 码元偏移。
    ///
    /// 遍历历史与当前屏幕时同步累加 UTF-16 长度，并保留光标定位所需的空白。
    fn snapshot_with_cursor(&self) -> (String, usize, Vec<TerminalStyleRange>) {
        let mut out = String::new();
        let mut prefix_len = 0;
        let mut styles = Vec::new();
        for row in &self.history {
            let kept = row
                .iter()
                .rposition(|cell| cell.ch != ' ')
                .map(|index| index + 1)
                .unwrap_or(0);
            append_cells(&mut out, &mut prefix_len, &mut styles, &row[..kept]);
            out.push('\n');
            prefix_len += 1;
        }

        // 保留到最后一个有内容的行或光标行，保证空白输入位置不会被裁掉。
        let mut last_non_empty = 0;
        for (i, row) in self.rows.iter().enumerate() {
            if row.iter().any(|cell| cell.ch != ' ') {
                last_non_empty = i + 1;
            }
        }
        let kept_len = last_non_empty.max(self.cur_r + 1).min(self.n_rows);
        let kept_rows = &self.rows[..kept_len];

        let mut cursor_off: Option<usize> = None;
        for (i, row) in kept_rows.iter().enumerate() {
            let mut kept = row
                .iter()
                .rposition(|cell| cell.ch != ' ')
                .map(|index| index + 1)
                .unwrap_or(0);
            if i == self.cur_r {
                kept = kept.max(self.cur_c);
                // 文本中宽字符只占 len_utf16 码元，占位格不产生文本。
                // 光标列 cur_c 指向宽字符的占位格时（row[cur_c] 是 pad），
                // 偏移需回退到该宽字符本体之前，让 UI 把整个汉字当作光标字符反色。
                let on_pad = self.cur_c < row.len() && row[self.cur_c].wide_pad;
                let mut col = 0usize;
                for cell in row.iter().take(self.cur_c) {
                    if !cell.wide_pad {
                        col += cell.ch.len_utf16();
                    }
                }
                if on_pad && self.cur_c > 0 {
                    // 本体在 row[cur_c-1]，回退其码元宽度，使偏移指向本体起始
                    let body = row[self.cur_c - 1];
                    col = col.saturating_sub(body.ch.len_utf16());
                }
                col += self.cur_c.saturating_sub(row.len());
                cursor_off = Some(prefix_len + col);
            }
            let existing = kept.min(row.len());
            append_cells(&mut out, &mut prefix_len, &mut styles, &row[..existing]);
            for _ in existing..kept {
                out.push(' ');
                prefix_len += 1;
            }
            out.push('\n');
            prefix_len += 1;
        }
        // 最后一行后的换行会被 ArkUI Text 渲染成额外空白行，使 tmux/rmux 状态栏
        // 与终端容器底部之间始终留出一行；行间换行保留，仅移除快照末尾换行。
        if out.ends_with('\n') {
            out.pop();
        }
        // 光标行越界时取快照末尾。
        let cursor = cursor_off.unwrap_or(utf16_len(&out)).min(utf16_len(&out));
        (out, cursor, styles)
    }
}

fn append_style_range(
    styles: &mut Vec<TerminalStyleRange>,
    start: usize,
    end: usize,
    style: &'static str,
    foreground: Option<String>,
    background: Option<String>,
) {
    if let Some(last) = styles.last_mut().filter(|range| {
        range.end == start
            && range.style == style
            && range.foreground == foreground
            && range.background == background
    }) {
        last.end = end;
    } else {
        styles.push(TerminalStyleRange {
            start,
            end,
            style,
            foreground,
            background,
        });
    }
}

fn append_cells(
    out: &mut String,
    prefix_len: &mut usize,
    styles: &mut Vec<TerminalStyleRange>,
    cells: &[Cell],
) {
    for cell in cells {
        // 宽字符占位格：只占列不渲染（列对齐已在 put_char 保证）
        if cell.wide_pad {
            continue;
        }
        let start = *prefix_len;
        out.push(cell.ch);
        *prefix_len += cell.ch.len_utf16();
        let style = if cell.inverse {
            "inverse"
        } else if cell.dim {
            "dim"
        } else if cell.bold {
            "bold"
        } else {
            "normal"
        };
        if style != "normal" || cell.foreground.is_some() || cell.background.is_some() {
            let foreground = cell.foreground.map(TerminalColor::css);
            let background = cell.background.map(TerminalColor::css);
            // 相邻同样式区间合并，减少 UI 分段数量
            append_style_range(styles, start, *prefix_len, style, foreground, background);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 剥离_csi颜色序列() {
        let (text, pending) = strip_ansi_escape("\x1b[1;31m你好\x1b[0m世界");
        assert_eq!(text, "你好世界");
        assert!(pending.is_empty());
    }

    #[test]
    fn 剥离_osc标题序列() {
        let (text, _) = strip_ansi_escape("\x1b]0;窗口标题\x07ls\r\n");
        assert_eq!(text, "ls\r\n");
        let (text2, _) = strip_ansi_escape("\x1b]8;;https://x\x1b\\链接\x1b]8;;\x1b\\");
        assert_eq!(text2, "链接");
    }

    #[test]
    fn 剥离_字符集选择序列() {
        let (text, _) = strip_ansi_escape("\x1b(Babc\x1b)0");
        assert_eq!(text, "abc");
    }

    #[test]
    fn 末尾不完整转义序列缓存() {
        let (text, pending) = strip_ansi_escape("abc\x1b[1;");
        assert_eq!(text, "abc");
        assert_eq!(pending, "\x1b[1;");
        // 下一块拼接后完整序列被剥离
        let (text2, pending2) = strip_ansi_escape(&format!("{pending}31mX"));
        assert_eq!(text2, "X");
        assert!(pending2.is_empty());
    }

    #[test]
    fn 末尾孤立esc与osc缓存() {
        let (text, pending) = strip_ansi_escape("abc\x1b");
        assert_eq!(text, "abc");
        assert_eq!(pending, "\x1b");
        let (_, pending2) = strip_ansi_escape("abc\x1b]0;标题");
        assert_eq!(pending2, "\x1b]0;标题");
    }

    #[test]
    fn 剥离杂散控制字符但保留换行回车制表() {
        let (text, _) = strip_ansi_escape("a\x07b\x0Bc\t\x1fd\x7fe\nf\rg");
        assert_eq!(text, "abc\tde\nf\rg");
    }

    #[test]
    fn cr行内覆盖() {
        assert_eq!(append_terminal_output("", "abcdef\rxy"), "xy");
        assert_eq!(append_terminal_output("ls\r\n", "down"), "ls\r\ndown");
    }

    #[test]
    fn cr连续合并不删除() {
        assert_eq!(append_terminal_output("abc", "\r\rxy"), "xy");
        assert_eq!(append_terminal_output("abc\r", "\r"), "abc\r");
    }

    #[test]
    fn cr块尾延迟判定() {
        // 块尾 \r 保留下一块：下一块以 \n 开头则正常换行
        let step1 = append_terminal_output("hello", "\r");
        assert_eq!(step1, "hello\r");
        let step2 = append_terminal_output(&step1, "\nworld");
        assert_eq!(step2, "hello\r\nworld");
        // 下一块以可见字符开头则覆盖当前行
        let step3 = append_terminal_output("hello\r", "HI");
        assert_eq!(step3, "HI");
    }

    #[test]
    fn 主屏退格擦除已显示字符() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"echo abc");
        assert_eq!(buf.feed(b"\x08 \x08\x08 \x08xy"), "echo axy");
    }

    #[test]
    fn 主屏输出ansi颜色并正确复位() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"plain \x1b[31mred\x1b[0m \x1b[48;2;1;2;3mbackground\x1b[49m");
        assert_eq!(buf.snapshot(), "plain red background");
        assert_eq!(
            buf.style_ranges(),
            &[
                TerminalStyleRange {
                    start: 6,
                    end: 9,
                    style: "normal",
                    foreground: Some("#CD3131".to_string()),
                    background: None,
                },
                TerminalStyleRange {
                    start: 10,
                    end: 20,
                    style: "normal",
                    foreground: None,
                    background: Some("#010203".to_string()),
                },
            ]
        );
    }

    #[test]
    fn 主屏保留粗体并用_sgr22_复位() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"plain \x1b[1mbold\x1b[22m plain");
        assert_eq!(buf.snapshot(), "plain bold plain");
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 6,
                end: 10,
                style: "bold",
                foreground: None,
                background: None,
            }]
        );
    }

    #[test]
    fn 备用屏保留跨读块粗体() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"\x1b[?1049h\x1b[1mBo");
        buf.feed(b"ld\x1b[22m normal");
        assert_eq!(buf.snapshot(), "Bold normal");
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 0,
                end: 4,
                style: "bold",
                foreground: None,
                background: None,
            }]
        );
    }

    #[test]
    fn 主屏颜色跨读块并随回车覆盖更新区间() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"\x1b[38;5;");
        buf.feed(b"196mold\r");
        buf.feed(b"new\x1b[0m");
        assert_eq!(buf.snapshot(), "new");
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 0,
                end: 3,
                style: "normal",
                foreground: Some("#FF0000".to_string()),
                background: None,
            }]
        );
    }

    #[test]
    fn 主屏颜色区间使用utf16偏移() {
        let mut buf = TerminalBuffer::new();
        buf.feed("前\x1b[34m😀蓝\x1b[0m后".as_bytes());
        assert_eq!(buf.snapshot(), "前😀蓝后");
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 1,
                end: 4,
                style: "normal",
                foreground: Some("#2473C8".to_string()),
                background: None,
            }]
        );
    }

    #[test]
    fn 缓冲增量喂入与快照截断() {
        let mut buf = TerminalBuffer::new();
        assert_eq!(buf.feed("\x1b[32mok\x1b[0m\r\n".as_bytes()), "ok\r\n");
        assert_eq!(buf.feed("next".as_bytes()), "ok\r\nnext");
    }

    #[test]
    fn utf8多字节跨块不丢失() {
        let mut buf = TerminalBuffer::new();
        let bytes = "中".as_bytes();
        assert_eq!(buf.feed(&bytes[..1]), "");
        assert_eq!(buf.feed(&bytes[1..]), "中");
    }

    #[test]
    fn 快照超长截断保留尾部() {
        let mut buf = TerminalBuffer::new();
        let big = "x".repeat(MAX_SNAPSHOT_BYTES + 100);
        let snapshot = buf.feed(big.as_bytes()).to_string();
        assert_eq!(snapshot.len(), MAX_SNAPSHOT_BYTES);
        assert!(snapshot.ends_with('x'));
    }

    #[test]
    fn 备用屏重绘不累积() {
        // 进入备用屏后清屏+重绘同一块内容，快照应只保留当前屏（不随重绘增长）
        let mut buf = TerminalBuffer::new();
        let draw = "\x1b[1;1H行一\x1b[K\r\n行二\x1b[K\r\n行三\x1b[K\r\n";
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        for _ in 0..5 {
            buf.feed(draw.as_bytes());
        }
        let snap = buf.snapshot().to_string();
        assert_eq!(snap.matches("行一").count(), 1);
        assert_eq!(snap.matches("行二").count(), 1);
        assert_eq!(snap.matches("行三").count(), 1);
    }

    #[test]
    fn 备用屏光标定位原地覆盖() {
        let mut buf = TerminalBuffer::new();
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        buf.feed("\x1b[1;1HAAAA\r\nBBBB\r\n".as_bytes());
        // 回到第一行原位改写
        buf.feed("\x1b[1;1HXX\x1b[K".as_bytes());
        let snap = buf.snapshot().to_string();
        assert!(snap.starts_with("XX\n"));
        assert!(snap.contains("BBBB"));
        assert!(!snap.contains("AAAA"));
    }

    #[test]
    fn 备用屏内容更新只显示最新值() {
        let mut buf = TerminalBuffer::new();
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        buf.feed("\x1b[1;1Htick=1\r\n".as_bytes());
        buf.feed("\x1b[1;1Htick=2\x1b[K\r\n".as_bytes());
        let snap = buf.snapshot().to_string();
        assert!(snap.contains("tick=2"));
        assert!(!snap.contains("tick=1"));
    }

    #[test]
    fn 退出备用屏恢复主屏() {
        let mut buf = TerminalBuffer::new();
        buf.feed("shell输出\r\n".as_bytes());
        buf.feed("\x1b[?1049h\x1b[2J\x1b[1;1HTUI画面\r\n".as_bytes());
        assert!(buf.snapshot().contains("TUI画面"));
        assert!(!buf.snapshot().contains("shell输出"));
        buf.feed("\x1b[?1049l".as_bytes());
        assert!(buf.snapshot().contains("shell输出"));
        assert!(!buf.snapshot().contains("TUI画面"));
    }

    #[test]
    fn 模拟tmux周期重绘快照稳定() {
        // 对齐真实捕获：进入备用屏后，周期性清屏+重写固定块+状态行，快照长度应稳定
        let mut buf = TerminalBuffer::with_rows(24);
        buf.feed("\x1b[?1049h\x1b[H\x1b[2J".as_bytes());
        let frame = "\x1b[1;1HQwen3.8-Max-Preview Model - ctx\x1b[K\r\n\
                     Get Day-One Access to Qwen 3.8\x1b[K\r\n\
                     Meet Kimi K3\x1b[K\r\n\
                     tick=T\x1b[K\r\n\
                     \x1b[30m\x1b[42m\r\n\
                     [term] 0:bash*\x1b[m";
        let mut last_len = 0;
        for i in 0..10 {
            buf.feed(frame.replace('T', &i.to_string()).as_bytes());
            last_len = buf.snapshot().len();
        }
        let snap = buf.snapshot().to_string();
        assert_eq!(snap.matches("Qwen3.8-Max-Preview").count(), 1);
        assert!(snap.contains("tick=9"));
        // 快照长度有界（远小于 10 帧累积）
        assert!(last_len < frame.len() * 3);
    }

    #[test]
    fn resize后备用屏底部内容不再丢失() {
        // 初始 5 行：画在第 7/8 行的内容被钳位折叠到第 5 行相互覆盖（模拟 PTY 未同步行数）
        let mut buf = TerminalBuffer::with_rows(5);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        buf.feed("\x1b[7;1Hstatus-bar".as_bytes());
        buf.feed("\x1b[8;1Hdialog".as_bytes());
        let snap = buf.snapshot().to_string();
        assert!(snap.contains("dialog"));
        assert!(!snap.contains("status-bar")); // 被折叠覆盖
                                               // resize 到 10 行（模拟 PTY resize 同步网格），重绘后两行内容各自可见
        buf.resize(10);
        buf.feed("\x1b[7;1Hstatus-bar".as_bytes());
        buf.feed("\x1b[8;1Hdialog".as_bytes());
        let snap = buf.snapshot().to_string();
        assert!(snap.contains("status-bar"));
        assert!(snap.contains("dialog"));
    }

    #[test]
    fn resize缩小行数不越界() {
        let mut buf = TerminalBuffer::with_rows(20);
        buf.feed("\x1b[?1049h\x1b[2J\x1b[15;1Hbottom".as_bytes());
        buf.resize(5);
        // 缩行后原第 15 行内容被截断，后续重绘不 panic 且快照正常
        buf.feed("\x1b[5;1Hnew-bottom".as_bytes());
        assert!(buf.snapshot().contains("new-bottom"));
    }

    #[test]
    fn 主屏光标偏移为快照末尾() {
        let mut buf = TerminalBuffer::new();
        buf.feed("ls\r\n".as_bytes());
        buf.feed("$ ".as_bytes());
        // 主屏模式：光标偏移 = 快照 UTF-16 长度
        assert_eq!(buf.cursor_offset(), buf.snapshot().chars().count());
        assert_eq!(buf.cursor_offset(), buf.snapshot().encode_utf16().count());
    }

    #[test]
    fn 备用屏光标偏移首行() {
        let mut buf = TerminalBuffer::with_rows(10);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        // 第1行写 "abc"，光标停在列 3（行内）
        buf.feed("\x1b[1;1Habc".as_bytes());
        let snap = buf.snapshot().to_string();
        assert_eq!(snap, "abc");
        // 光标在第1行第3列 → 偏移 3
        assert_eq!(buf.cursor_offset(), 3);
    }

    #[test]
    fn 备用屏_csi保存恢复光标() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049hinput\x1b[s placeholder\x1b[u".as_bytes());
        assert_eq!(buf.cursor_offset(), "input".encode_utf16().count());
    }

    #[test]
    fn 备用屏光标偏移中间行() {
        let mut buf = TerminalBuffer::with_rows(10);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        // 第1行 "AAAA"，第2行 "BBBB"，光标停在第2行第2列
        buf.feed("\x1b[1;1HAAAA\r\nBBBB".as_bytes());
        let snap = buf.snapshot().to_string();
        assert_eq!(snap, "AAAA\nBBBB");
        // 第1行 4 字符 + 换行 = 5，第2行写完 BBBB 光标在列 4
        assert_eq!(buf.cursor_offset(), 5 + 4);
    }

    #[test]
    fn 备用屏光标偏移保留行尾空格() {
        let mut buf = TerminalBuffer::with_rows(10);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        // 第1行 "ABC"，光标移到第1行第10列，保留定位所需的 6 个空格。
        buf.feed("\x1b[1;1HABC\x1b[1;10H".as_bytes());
        assert_eq!(buf.snapshot(), "ABC      ");
        assert_eq!(buf.cursor_offset(), 9);
    }

    #[test]
    fn 备用屏光标落在尾部空行时保留光标行() {
        let mut buf = TerminalBuffer::with_rows(10);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        // 第1行有内容，光标移到第5行（纯空行，会被裁掉）
        buf.feed("\x1b[1;1Hhello\x1b[5;1H".as_bytes());
        let snap = buf.snapshot().to_string();
        assert_eq!(snap, "hello\n\n\n\n");
        assert_eq!(buf.cursor_offset(), "hello\n\n\n\n".encode_utf16().count());
    }

    #[test]
    fn 备用屏emoji后光标使用utf16偏移() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h😀".as_bytes());
        // 😀 占 2 码元（UTF-16），占位格不产生文本，光标偏移 = 2
        assert_eq!(buf.cursor_offset(), 2);
    }

    #[test]
    fn 备用屏保留光标所在空白位置() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h标题\x1b[3;5H".as_bytes());
        assert_eq!(buf.snapshot(), "标题\n\n    ");
        assert_eq!(buf.cursor_offset(), "标题\n\n    ".encode_utf16().count());
    }

    #[test]
    fn 备用屏上滚内容进入历史() {
        let mut buf = TerminalBuffer::with_rows(2);
        buf.feed("\x1b[?1049h一\r\n二\r\n三".as_bytes());
        assert!(buf.snapshot().starts_with("一\n"));
        assert!(buf.snapshot().ends_with("二\n三"));
    }

    #[test]
    fn 备用屏输出弱化样式区间() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h正常\x1b[2m提示\x1b[22m正文".as_bytes());
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 2,
                end: 4,
                style: "dim",
                foreground: None,
                background: None,
            }]
        );
    }

    #[test]
    fn 备用屏宽字符占两列保持对齐() {
        // 远端按 wcwidth 排版：中文占 2 列，表格竖线应落在同一列。
        // tmux 重绘含中文的行时是整行重写（不会把光标定位到半个宽字符中间），
        // 这里模拟两行表格整行重绘，竖线必须逐列对齐。
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h\x1b[2J".as_bytes());
        buf.feed("\x1b[1;1H│名称│\x1b[2;1H│值 │".as_bytes());
        let snap = buf.snapshot().to_string();
        let lines: Vec<&str> = snap.lines().collect();
        assert_eq!(lines[0], "│名称│");
        assert_eq!(lines[1], "│值 │");
        // 整行重绘（中文内容变化），右竖线仍须对齐在同一列
        buf.feed("\x1b[1;1H│备注│\x1b[2;1H│数量│".as_bytes());
        let snap = buf.snapshot().to_string();
        let lines: Vec<&str> = snap.lines().collect();
        assert_eq!(lines[0], "│备注│");
        assert_eq!(lines[1], "│数量│");
    }

    #[test]
    fn 备用屏按pty列宽自动换行() {
        let mut buf = TerminalBuffer::with_size(5, 4);
        buf.feed("\x1b[?1049habcdef".as_bytes());
        assert_eq!(buf.snapshot(), "abcde\nf");
    }

    #[test]
    fn 备用屏调整列宽后不保留越界旧内容() {
        let mut buf = TerminalBuffer::with_size(8, 4);
        buf.feed("\x1b[?1049h12345678X".as_bytes());
        assert_eq!(buf.snapshot(), "12345678\nX");

        buf.resize_size(5, 4);
        buf.feed("\x1b[1;1Habc\x1b[K".as_bytes());
        assert_eq!(buf.snapshot(), "abc\nX");
    }

    #[test]
    fn 备用屏宽字符被覆盖不残留半字() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h中".as_bytes());
        // 在列 1（宽字符的占位格）写入窄字符，左侧半个宽字符应被抹掉
        buf.feed("\x1b[1;2Hab".as_bytes());
        let snap = buf.snapshot().to_string();
        assert_eq!(snap.lines().next().unwrap(), " ab");
    }

    #[test]
    fn 备用屏光标落在宽字符上时偏移指向本体() {
        let mut buf = TerminalBuffer::with_rows(4);
        // "中文"：中占 col0-1，文占 col2-3
        buf.feed("\x1b[?1049h中文".as_bytes());
        // 光标移到第 2 列（1 起 col 2 = 0 起 col 1 = "中"的占位格）
        buf.feed("\x1b[1;2H".as_bytes());
        // 偏移应指向"中"本体（UTF-16 偏移 0），让 UI 反色整个"中"
        assert_eq!(buf.cursor_offset(), 0);
        // 光标移到第 3 列（0 起 col 2 = "文"本体）
        buf.feed("\x1b[1;3H".as_bytes());
        assert_eq!(buf.cursor_offset(), 1);
    }

    #[test]
    fn 备用屏输出反色样式区间() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h\x1b[7m[bot] 0:bash*\x1b[27m normal".as_bytes());
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 0,
                end: 13,
                style: "inverse",
                foreground: None,
                background: None,
            }]
        );
        // SGR 0 也应复位反色
        let mut buf2 = TerminalBuffer::with_rows(4);
        buf2.feed("\x1b[?1049h\x1b[7mAB\x1b[0mCD".as_bytes());
        assert_eq!(
            buf2.style_ranges(),
            &[TerminalStyleRange {
                start: 0,
                end: 2,
                style: "inverse",
                foreground: None,
                background: None,
            }]
        );
    }

    #[test]
    fn 备用屏输出tmux显式前景与背景色() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h普通\x1b[30;42m[rmux] 状态栏\x1b[0m正文".as_bytes());
        assert_eq!(
            buf.style_ranges(),
            &[TerminalStyleRange {
                start: 2,
                end: 12,
                style: "normal",
                foreground: Some("#000000".to_string()),
                background: Some("#0DAC59".to_string()),
            }]
        );
    }

    #[test]
    fn 备用屏输出256色与rgb色并正确复位() {
        let mut buf = TerminalBuffer::with_rows(4);
        buf.feed("\x1b[?1049h\x1b[38;5;196m红\x1b[48;2;1;2;3m底\x1b[39;49m普通".as_bytes());
        assert_eq!(
            buf.style_ranges(),
            &[
                TerminalStyleRange {
                    start: 0,
                    end: 1,
                    style: "normal",
                    foreground: Some("#FF0000".to_string()),
                    background: None,
                },
                TerminalStyleRange {
                    start: 1,
                    end: 2,
                    style: "normal",
                    foreground: Some("#FF0000".to_string()),
                    background: Some("#010203".to_string()),
                },
            ]
        );
    }

    #[test]
    fn 备用屏_ech擦除行尾残留() {
        // tmux split-window 重绘裁剪行时发 `\x1b[<n>X` 抹掉右侧旧内容；
        // 未实现 ECH 时旧字符残留在新短行之后
        let mut buf = TerminalBuffer::with_size(10, 4);
        buf.feed("\x1b[?1049h\x1b[2J\x1b[1;1Habcdefghij".as_bytes());
        buf.feed("\x1b[1;1Hab\x1b[8X".as_bytes());
        assert_eq!(buf.snapshot(), "ab");
    }

    #[test]
    fn 备用屏_dch删除字符左移() {
        let mut buf = TerminalBuffer::with_size(10, 4);
        buf.feed("\x1b[?1049h\x1b[2J\x1b[1;1Habcdef".as_bytes());
        buf.feed("\x1b[1;2H\x1b[2P".as_bytes());
        assert_eq!(buf.snapshot(), "adef");
    }

    #[test]
    fn 备用屏_ich插入空白右移且截断() {
        let mut buf = TerminalBuffer::with_size(6, 4);
        buf.feed("\x1b[?1049h\x1b[2J\x1b[1;1Habcdef".as_bytes());
        buf.feed("\x1b[1;2H\x1b[2@".as_bytes());
        assert_eq!(buf.snapshot(), "a  bcd");
    }

    #[test]
    fn 备用屏_il_dl滚动区域内插删行() {
        let mut buf = TerminalBuffer::with_size(10, 3);
        buf.feed("\x1b[?1049h\x1b[2J\x1b[1;1H一\r\n二\r\n三".as_bytes());
        // IL：在第 1 行插入空行，"三"被挤出滚动区
        buf.feed("\x1b[1;1H\x1b[L".as_bytes());
        assert_eq!(buf.snapshot(), "\n一\n二");
        // DL：删除第 1 行，"一"上移到第 1 行
        buf.feed("\x1b[1;1H\x1b[M".as_bytes());
        assert_eq!(buf.snapshot(), "一\n二");
    }

    #[test]
    fn 鼠标跟踪模式启停并优先使用sgr编码() {
        let mut buf = TerminalBuffer::new();
        assert_eq!(buf.mouse_protocol(), "none");

        buf.feed(b"\x1b[?1000h");
        assert_eq!(buf.mouse_protocol(), "x10");
        buf.feed(b"\x1b[?1006h");
        assert_eq!(buf.mouse_protocol(), "sgr");

        // 关闭一个跟踪模式时，仍启用的另一个模式必须继续生效。
        buf.feed(b"\x1b[?1002h\x1b[?1000l");
        assert_eq!(buf.mouse_protocol(), "sgr");
        buf.feed(b"\x1b[?1002l");
        assert_eq!(buf.mouse_protocol(), "none");
    }

    #[test]
    fn 组合dec私有模式可同时控制鼠标跟踪和sgr() {
        let mut buf = TerminalBuffer::new();
        buf.feed(b"\x1b[?1000;1003;1006h");
        assert_eq!(buf.mouse_protocol(), "sgr");
        buf.feed(b"\x1b[?1000;1003;1006l");
        assert_eq!(buf.mouse_protocol(), "none");
    }
}
