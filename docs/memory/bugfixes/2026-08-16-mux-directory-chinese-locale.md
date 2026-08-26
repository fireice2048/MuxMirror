# BugFix 记忆：MUX 按目录分组丢失中文目录名

## 现象

- 触发条件：鸿蒙端将 MUX 导航设置为“按目录分组”，工作目录包含中文（现场为 `~/Working/Yanghan/直播`）。
- 用户影响：导航标题显示为 `~/Working/Yanghan/____`，无法识别真实中文目录。

## 根因

- 移动端通过非交互 SSH exec 执行 `muxmirror -format json --mux --by-directory`。
- SSH exec channel 不加载 shell 配置，远端环境可能没有 `LANG` / `LC_ALL`；tmux 在非 UTF-8 locale 下会把 `pane_current_path` 的非 ASCII 字符转写成下划线。
- 对照验证：清空 locale 后 `直播` 稳定输出为 `____`，设置 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` 后恢复原中文。

## 修复方案

- 涉及模块：`MobileApp/shared/src/session/mod.rs`、终端保真需求文档。
- 关键改动：在 SSH exec 公共命令包装层显式导出 UTF-8 locale，并保留既有 PATH 补齐逻辑；所有复用连接和独立连接的 exec 通道共同生效。
- 新增单元测试，约束 UTF-8 locale、工具路径和原始命令均存在于最终远端命令中。

## 验证方式

- 复现步骤：按目录分组进入导航页，检查包含中文的工作目录标题。
- 验证命令：`cargo test`、鸿蒙双 ABI Rust 交叉编译、签名 HAP 真机覆盖安装及截图。
- 验证结果：Rust 单元测试 82 项全部通过；arm64-v8a 与 x86_64 OHOS Rust 核心交叉编译、clean debug HAP 构建均通过；签名 HAP 已覆盖安装到 HUAWEI Pura 70 真机和 Pura 90 Pro 模拟器。模拟器按目录分组页面现场显示 `~/Working/Yanghan/直播`，不再出现 `____`。

## 预防措施

- 所有依赖远端文本编码的非交互 SSH 命令都应在公共 exec 包装层统一提供 UTF-8 locale，不能依赖用户 shell 初始化文件。
- 验收目录、标题和 JSON 传输时必须包含至少一个非 ASCII 路径样例。
