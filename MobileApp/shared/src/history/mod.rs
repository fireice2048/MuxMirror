//! 命令历史模块。
//!
//! 记录用户在终端中执行过的命令，支持向上 / 向下翻阅（对齐 shell 的 ↑/↓ 行为）。
//! MVP 仅内存保存，随会话创建；持久化后续按需补充。

/// 命令历史：追加记录 + 光标导航。
#[derive(Default)]
pub struct CommandHistory {
    entries: Vec<String>,
    /// 翻阅光标：None 表示未在翻阅（新输入状态）；
    /// Some(i) 表示当前展示 entries[i]
    cursor: Option<usize>,
}

impl CommandHistory {
    /// 创建空历史。
    pub fn new() -> Self {
        Self::default()
    }

    /// 追加一条命令（空命令或与上一条重复时不入库），并复位翻阅光标。
    pub fn add(&mut self, command: &str) {
        let command = command.trim();
        if command.is_empty() {
            return;
        }
        if self.entries.last().map(String::as_str) != Some(command) {
            self.entries.push(command.to_string());
        }
        self.cursor = None;
    }

    /// 上一条（↑）：向更早方向移动光标；到顶后保持。
    pub fn prev(&mut self) -> Option<&str> {
        if self.entries.is_empty() {
            return None;
        }
        let index = match self.cursor {
            None => self.entries.len() - 1,
            Some(0) => 0,
            Some(i) => i - 1,
        };
        self.cursor = Some(index);
        Some(&self.entries[index])
    }

    /// 下一条（↓）：向更新方向移动光标；越过最后一条后回到 None（新输入状态）。
    pub fn next(&mut self) -> Option<&str> {
        let index = match self.cursor {
            None => return None,
            Some(i) if i + 1 >= self.entries.len() => {
                self.cursor = None;
                return None;
            }
            Some(i) => i + 1,
        };
        self.cursor = Some(index);
        Some(&self.entries[index])
    }

    /// 历史条数。
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// 历史是否为空。
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 空命令与连续重复命令不入库() {
        let mut history = CommandHistory::new();
        history.add("   ");
        history.add("ls");
        history.add("ls");
        history.add("pwd");
        assert_eq!(history.len(), 2);
    }

    #[test]
    fn 上下翻阅行为对齐shell() {
        let mut history = CommandHistory::new();
        history.add("ls");
        history.add("pwd");
        history.add("top");
        assert_eq!(history.prev(), Some("top"));
        assert_eq!(history.prev(), Some("pwd"));
        assert_eq!(history.prev(), Some("ls"));
        assert_eq!(history.prev(), Some("ls")); // 到顶保持
        assert_eq!(history.next(), Some("pwd"));
        assert_eq!(history.next(), Some("top"));
        assert_eq!(history.next(), None); // 回到新输入
        assert_eq!(history.prev(), Some("top")); // 重新翻阅
    }

    #[test]
    fn 追加命令复位翻阅光标() {
        let mut history = CommandHistory::new();
        history.add("a");
        history.add("b");
        history.prev();
        history.add("c");
        assert_eq!(history.prev(), Some("c"));
    }
}
