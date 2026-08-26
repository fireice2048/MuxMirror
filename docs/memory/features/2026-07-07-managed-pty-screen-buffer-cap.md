# 功能记忆：managed PTY screen buffer 上限

## 背景

- 需求来源：managed PTY 已支持长期输入输出，累计 screen 字符串如果不限制会持续增长。
- 使用场景：长时间运行命令或大量输出时，服务端不能无限占用内存。

## 关键功能点

- managed PTY screen buffer 限制为最近 200KB 输出。
- 每次 drain PTY 输出后执行裁剪。
- 裁剪保持 UTF-8 字符边界。

## 设计与实现

- 涉及模块：`PCServer/attach/src/pty.rs`。
- 核心流程：读取 PTY 输出 → 追加到 screen → 超过上限则删除最旧内容。
- 重要约束：当前是简单滚动字符串，不是完整终端屏幕模型或 ANSI 解析器。

## 验证方式

- 命令：`cargo test -p attach`
- 结果：单元测试通过，覆盖 screen 裁剪到上限并保留最近输出。

## 后续注意事项

- 后续终端 UI 需要 ANSI 解析和行列缓冲区，不能长期依赖纯字符串快照。
