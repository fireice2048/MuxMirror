//! TermMirror 终端核心库。
//!
//! 本 crate 承载三端（Android / iOS / HarmonyOS）共享的全部终端逻辑：
//! SSH 会话管理、ANSI 解析与屏幕缓冲、键盘输入编码、命令历史、配置模型与日志。
//! 三端原生 UI 通过 [`ffi`] 暴露的 C ABI 薄层与本核心交互，
//! 原生层只做展示与交互，不实现任何终端逻辑。

pub mod config;
pub mod ffi;
pub mod history;
pub mod input;
pub mod log;
pub mod session;
pub mod terminal;

/// 核心库版本号，供 FFI 层上报给三端 UI 做兼容性诊断。
pub const CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    #[test]
    fn 暴露版本号() {
        assert!(!super::CORE_VERSION.is_empty());
    }
}
