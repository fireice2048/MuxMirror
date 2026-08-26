//! 调试示例：重放捕获的终端字节流，输出最终快照（供与 pyte 等参照实现对比）。
use std::io::Read;

fn main() {
    let path = std::env::args().nth(1).expect("用法: replay <raw文件>");
    let mut f = std::fs::File::open(&path).expect("无法打开输入文件");
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).expect("读取失败");
    let mut term = termirror_core::terminal::TerminalBuffer::with_size(43, 37);
    // 模拟设备端分块喂入（SSH 读块通常 4KB 左右）
    for chunk in buf.chunks(997) {
        term.feed(chunk);
    }
    let snap = term.snapshot().to_string();
    for (i, line) in snap.lines().enumerate() {
        println!("{:2}|{}|", i + 1, line);
    }
}
