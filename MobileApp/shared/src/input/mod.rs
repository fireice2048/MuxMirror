//! 键盘输入编码模块。
//!
//! 把三端原生层上报的按键（可打印字符或命名键）编码为终端字节序列。
//! 修饰键语义对齐原 Kotlin 实现（`App.kt` 的 `applyTerminalModifiers` /
//! `xtermFunctionSequence` / `xtermTildeSequence`）：
//! - CTRL：字母与 `@`..`_` 映射为控制字符（`c & 0x1F`），另含空格/`/`/`|`/`?` 特例；
//! - ALT：输出前加 ESC 前缀；
//! - 方向键 / HOME / END：xterm CSI 功能键修饰参数（Alt=3、Ctrl=5、Ctrl+Alt=7）；
//! - DEL / PGUP / PGDN / F5-F12：xterm `CSI n~` 系列；
//! - F1-F4：xterm SS3（`ESC O P/Q/R/S`），带修饰键时为 `CSI 1;m P/Q/R/S`。

/// 特殊按键集合（契约中 tmEncodeKey 支持的命名键）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NamedKey {
    Esc,
    Tab,
    Enter,
    Backspace,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Delete,
    /// F1-F12，取值为功能键编号（1-12）
    Function(u8),
}

/// 解析契约中的命名键字符串；非命名键返回 None（按可打印文本处理）。
fn parse_named_key(key: &str) -> Option<NamedKey> {
    Some(match key {
        "ESC" => NamedKey::Esc,
        "TAB" => NamedKey::Tab,
        "ENTER" => NamedKey::Enter,
        "BACKSPACE" => NamedKey::Backspace,
        "UP" => NamedKey::Up,
        "DOWN" => NamedKey::Down,
        "LEFT" => NamedKey::Left,
        "RIGHT" => NamedKey::Right,
        "HOME" => NamedKey::Home,
        "END" => NamedKey::End,
        "PGUP" => NamedKey::PageUp,
        "PGDN" => NamedKey::PageDown,
        "DEL" => NamedKey::Delete,
        _ => {
            let number = key.strip_prefix('F')?.parse::<u8>().ok()?;
            if (1..=12).contains(&number) && key.len() == number.to_string().len() + 1 {
                NamedKey::Function(number)
            } else {
                return None;
            }
        }
    })
}

/// 契约入口：把按键编码为终端字节序列（以 String 返回，内部可含控制字符）。
///
/// `key` 为可打印字符本身（或一段文本，逐字符套用修饰键），或命名键字符串。
pub fn encode_key(key: &str, ctrl: bool, alt: bool) -> String {
    match parse_named_key(key) {
        Some(named) => encode_named_key(named, ctrl, alt),
        None => apply_modifiers(key, ctrl, alt),
    }
}

/// 命名键编码。
fn encode_named_key(key: NamedKey, ctrl: bool, alt: bool) -> String {
    match key {
        NamedKey::Esc => {
            if alt {
                "\x1b\x1b".to_string()
            } else {
                "\x1b".to_string()
            }
        }
        NamedKey::Tab => apply_modifiers("\t", ctrl, alt),
        NamedKey::Enter => apply_modifiers("\r", ctrl, alt),
        NamedKey::Backspace => {
            if alt {
                "\x1b\x7f".to_string()
            } else {
                "\x7f".to_string()
            }
        }
        NamedKey::Up => xterm_function_sequence("\x1b[A", 'A', ctrl, alt),
        NamedKey::Down => xterm_function_sequence("\x1b[B", 'B', ctrl, alt),
        NamedKey::Right => xterm_function_sequence("\x1b[C", 'C', ctrl, alt),
        NamedKey::Left => xterm_function_sequence("\x1b[D", 'D', ctrl, alt),
        NamedKey::Home => xterm_function_sequence("\x1b[H", 'H', ctrl, alt),
        NamedKey::End => xterm_function_sequence("\x1b[F", 'F', ctrl, alt),
        NamedKey::PageUp => xterm_tilde_sequence(5, ctrl, alt),
        NamedKey::PageDown => xterm_tilde_sequence(6, ctrl, alt),
        NamedKey::Delete => xterm_tilde_sequence(3, ctrl, alt),
        NamedKey::Function(n) => encode_function_key(n, ctrl, alt),
    }
}

/// F1-F12 功能键编码（xterm）。
fn encode_function_key(n: u8, ctrl: bool, alt: bool) -> String {
    // F1-F4：SS3 序列；带修饰键时退化为 CSI 形式
    let ss3_final = match n {
        1 => Some('P'),
        2 => Some('Q'),
        3 => Some('R'),
        4 => Some('S'),
        _ => None,
    };
    if let Some(final_char) = ss3_final {
        if !ctrl && !alt {
            return format!("\x1bO{final_char}");
        }
        let modifier = modifier_param(ctrl, alt);
        return format!("\x1b[1;{modifier}{final_char}");
    }
    // F5-F12：CSI n~ 序列
    let number = match n {
        5 => 15,
        6 => 17,
        7 => 18,
        8 => 19,
        9 => 20,
        10 => 21,
        11 => 23,
        12 => 24,
        _ => unreachable!("F 键编号已限定在 1-12"),
    };
    xterm_tilde_sequence(number, ctrl, alt)
}

/// 逐字符套用 CTRL/ALT 修饰键（对齐 Kotlin `applyTerminalModifiers`）。
pub fn apply_modifiers(text: &str, ctrl: bool, alt: bool) -> String {
    let mut out = String::with_capacity(text.len() + if alt { text.len() } else { 0 });
    for ch in text.chars() {
        if alt {
            out.push('\x1b');
        }
        out.push(if ctrl {
            control_character(ch).unwrap_or(ch)
        } else {
            ch
        });
    }
    out
}

/// CTRL 组合的控制字符映射（对齐 Kotlin `terminalControlCharacter`）。
fn control_character(ch: char) -> Option<char> {
    match ch {
        'a'..='z' => char::from_u32((ch.to_ascii_uppercase() as u32) & 0x1F),
        '@'..='_' => char::from_u32((ch as u32) & 0x1F),
        ' ' => Some('\x00'),
        '/' => Some('\x1F'),
        '|' => Some('\x1C'),
        '?' => Some('\x7F'),
        _ => None,
    }
}

/// xterm 修饰键参数：Alt=3、Ctrl=5、Ctrl+Alt=7（1 + Alt*2 + Ctrl*4）。
fn modifier_param(ctrl: bool, alt: bool) -> u8 {
    1 + if alt { 2 } else { 0 } + if ctrl { 4 } else { 0 }
}

/// xterm CSI 功能键序列（对齐 Kotlin `xtermFunctionSequence`）。
fn xterm_function_sequence(plain: &str, final_char: char, ctrl: bool, alt: bool) -> String {
    if !ctrl && !alt {
        return plain.to_string();
    }
    format!("\x1b[1;{}{final_char}", modifier_param(ctrl, alt))
}

/// xterm `CSI n~` 序列（对齐 Kotlin `xtermTildeSequence`）。
fn xterm_tilde_sequence(number: u8, ctrl: bool, alt: bool) -> String {
    if !ctrl && !alt {
        return format!("\x1b[{number}~");
    }
    format!("\x1b[{number};{}~", modifier_param(ctrl, alt))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 可打印字符原样输出() {
        assert_eq!(encode_key("a", false, false), "a");
        assert_eq!(encode_key("中", false, false), "中");
    }

    #[test]
    fn esc与tab与回车退格() {
        assert_eq!(encode_key("ESC", false, false), "\x1b");
        assert_eq!(encode_key("ESC", false, true), "\x1b\x1b");
        assert_eq!(encode_key("TAB", false, false), "\t");
        assert_eq!(encode_key("ENTER", false, false), "\r");
        assert_eq!(encode_key("BACKSPACE", false, false), "\x7f");
    }

    #[test]
    fn 方向键与修饰键() {
        assert_eq!(encode_key("UP", false, false), "\x1b[A");
        assert_eq!(encode_key("DOWN", false, false), "\x1b[B");
        assert_eq!(encode_key("RIGHT", false, false), "\x1b[C");
        assert_eq!(encode_key("LEFT", false, false), "\x1b[D");
        // Ctrl+上：CSI 1;5A
        assert_eq!(encode_key("UP", true, false), "\x1b[1;5A");
        // Alt+左：CSI 1;3D
        assert_eq!(encode_key("LEFT", false, true), "\x1b[1;3D");
        // Ctrl+Alt+右：CSI 1;7C
        assert_eq!(encode_key("RIGHT", true, true), "\x1b[1;7C");
    }

    #[test]
    fn home_end_del翻页() {
        assert_eq!(encode_key("HOME", false, false), "\x1b[H");
        assert_eq!(encode_key("END", false, false), "\x1b[F");
        assert_eq!(encode_key("DEL", false, false), "\x1b[3~");
        assert_eq!(encode_key("DEL", true, false), "\x1b[3;5~");
        assert_eq!(encode_key("PGUP", false, false), "\x1b[5~");
        assert_eq!(encode_key("PGDN", false, false), "\x1b[6~");
        assert_eq!(encode_key("PGUP", false, true), "\x1b[5;3~");
    }

    #[test]
    fn 功能键f1到f12() {
        assert_eq!(encode_key("F1", false, false), "\x1bOP");
        assert_eq!(encode_key("F2", false, false), "\x1bOQ");
        assert_eq!(encode_key("F3", false, false), "\x1bOR");
        assert_eq!(encode_key("F4", false, false), "\x1bOS");
        assert_eq!(encode_key("F1", true, false), "\x1b[1;5P");
        assert_eq!(encode_key("F5", false, false), "\x1b[15~");
        assert_eq!(encode_key("F6", false, false), "\x1b[17~");
        assert_eq!(encode_key("F10", false, false), "\x1b[21~");
        assert_eq!(encode_key("F11", false, false), "\x1b[23~");
        assert_eq!(encode_key("F12", false, false), "\x1b[24~");
        assert_eq!(encode_key("F12", true, true), "\x1b[24;7~");
    }

    #[test]
    fn ctrl组合控制字符() {
        assert_eq!(encode_key("c", true, false), "\x03"); // Ctrl+C
        assert_eq!(encode_key("d", true, false), "\x04"); // Ctrl+D
        assert_eq!(encode_key("z", true, false), "\x1a"); // Ctrl+Z
        assert_eq!(encode_key("[", true, false), "\x1b"); // Ctrl+[
        assert_eq!(encode_key("?", true, false), "\x7f"); // Ctrl+?
        assert_eq!(encode_key(" ", true, false), "\x00"); // Ctrl+Space
                                                          // 无映射的字符保持原样
        assert_eq!(encode_key("1", true, false), "1");
    }

    #[test]
    fn alt前缀() {
        assert_eq!(encode_key("x", false, true), "\x1bx"); // Alt+x
        assert_eq!(encode_key("c", true, true), "\x1b\x03"); // Ctrl+Alt+C
    }
}
