# muxmirror 安装期权限引导实施计划

## 方案

将当前内嵌于 Rust 字符串、运行时编译到 `/tmp` 的 Swift AX Helper 拆为独立源码。安装脚本把它编译到稳定用户目录；Rust 主程序只调用该稳定 Helper，并增加 setup/doctor 命令。

## 任务

- [x] 拆出稳定 Swift AX Helper 源码。
- [x] Helper 支持 `--check-permission`、`--request-permission` 和默认窗口枚举。
- [x] Rust CLI 增加 `setup`、`doctor`。
- [x] 移除运行时 Swift 编译和 `/tmp` Helper。
- [x] 正常扫描对 Helper 缺失、权限缺失返回明确错误。
- [x] 新增 `scripts/install-muxmirror.sh`。
- [x] 安装脚本支持临时前缀和跳过权限 prompt，便于自动测试。
- [x] 更新 README、验收文档和记忆文档。
- [x] 执行格式、测试、release 构建和临时安装验收。
- [ ] 清理旧安装与旧权限主体。

## 提交里程碑

1. 文档：记录安装期权限引导需求与计划。
2. 核心：稳定 Helper 与 setup/doctor。
3. 安装：安装脚本、说明和验证。
4. 清理：只处理本机旧安装，不把机器状态写入仓库提交。
