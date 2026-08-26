# 鸿蒙服务器列表拖动排序验收记录

日期：2026-07-22

## 环境

- 模拟器：Pura 90 Pro New（`127.0.0.1:5555`）
- 应用：`com.attach.mobile.harmony`
- 安装方式：使用 signed HAP 覆盖安装，保留现有应用数据

## 验收结果

- [x] 列表项长按后可使用 ArkUI 原生浮起跟手效果调整顺序。
- [x] 拖动落位后列表立即更新；实测 `ProbeServer` 从第五项移到第一项。
- [x] 强制结束应用并重新启动后，`ProbeServer` 仍位于第一项，证明新顺序已持久化。
- [x] 右侧编辑、复制、删除三个按钮水平占用缩短，布局无遮挡。
- [x] 顶部 banner 保持原高度并左对齐，稳定启动后截图确认已生效。
- [x] Rust 双 ABI 交叉编译通过，`devecocli build clean` 后 signed HAP 构建通过。

## 自动化证据

- `cargo test`：47 项通过，0 失败。
- `bash scripts/build-ohos.sh`：`aarch64-unknown-linux-ohos` 与 `x86_64-unknown-linux-ohos` 均构建成功。
- `devecocli build clean && devecocli build --build-mode debug`：构建成功。
