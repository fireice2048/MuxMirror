# 功能记忆：muxmirror JSON 输出标签页当前路径（cwd）

## 背景

- 需求来源：用户希望 `muxmirror -format json` 输出每个终端标签页的当前工作目录。
- 使用场景：MobileApp 导航浮层（`TerminalNavPanel.ets`）通过 SSH exec 执行 `muxmirror -format json --mux` 拉取窗口/标签页列表，cwd 可用于展示每个标签页所在路径。

## 关键功能点

- `TabInfoJson` 新增 `cwd` 字段，JSON 输出中每个 tab 均携带 `cwd`。
- cwd 取值优先级：`AXDocument`（终端实际 document 路径）> 标题提取目录（须以 `/` 开头的绝对路径）> 匹配到的 mux session 的 shell CWD。
- 标题提取目录做了 `starts_with('/')` 校验，避免把"✳ 重启后 SpiritBot 服务仍未启动"这类非路径标题误当 cwd。
- 无法确定时 `cwd` 为空字符串。

## 设计与实现

- 涉及模块：`MirrorServer/src/main.rs`（`TabInfoJson`、`print_json`）。
- 核心流程：`print_json` 中逐 tab 计算 cwd——优先复用已有的 `ax_document`（macOS AX 属性），其次用 `extract_dir_from_title` 解析标题首段，最后回退到 `mux_sessions` 中已匹配 session 的 `shell_cwd`。
- 重要约束：`ax_document` 与标题目录均需排除等于 `$HOME` 的情况（视为无有效路径）；标题目录必须是以 `/` 开头的绝对路径。

## 验证方式

- 命令：`cargo install --path MirrorServer --force && muxmirror -format json`
- 结果：含路径标题的 tab 输出正确 cwd（如 `/Users/xpeng/Working/gitee/term-hook`）；标题无路径信息的 rmux tab cwd 为 `""`；`--mux` 过滤下同样正常。

## 后续注意事项

- 部署到本机用 `cargo install --path MirrorServer --force`（二进制安装到 `~/.cargo/bin/muxmirror`）。
- 消费方 `TerminalNavPanel.ets` 的 `NavTab` 结构如要展示 cwd，需自行添加该字段（当前未消费）。
