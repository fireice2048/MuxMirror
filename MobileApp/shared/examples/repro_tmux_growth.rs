//! 复现：把真实捕获的 tmux attach 字节流喂给 TerminalBuffer，观察快照增长。
//! 用法：cargo run --example repro_tmux_growth -- /tmp/capture.bin
use std::fs;

fn main() {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/tmp/capture.bin".to_string());
    let data = fs::read(&path).expect("读取捕获文件失败");
    let mut buf = termirror_core::terminal::TerminalBuffer::new();

    // 模拟 SSH 分块：按 512 字节喂入，每喂一块记录快照长度
    println!("总字节数: {}", data.len());
    let mut prev_len = 0;
    for (i, chunk) in data.chunks(512).enumerate() {
        let snap_len = buf.feed(chunk).len();
        println!(
            "chunk#{:02} (+{:4}B) => 快照长度 {} 字节",
            i,
            chunk.len(),
            snap_len
        );
        prev_len = snap_len;
    }
    let _ = prev_len;

    println!("\n===== 最终快照（可见形式，前 1200 字符）=====");
    let snap = buf.snapshot();
    let visible: String = snap
        .chars()
        .take(1200)
        .map(|c| match c {
            '\x1b' => '§',
            '\r' => '␍',
            c => c,
        })
        .collect();
    println!("{visible}");
    println!(
        "\n快照总长: {} 字节；其中 'Qwen3.8-Max-Preview' 出现 {} 次（每次重绘应只出现 1 次）",
        snap.len(),
        snap.matches("Qwen3.8-Max-Preview").count()
    );
}
