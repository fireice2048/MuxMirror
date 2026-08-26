# 功能记忆：安装脚本

## 背景

- 需求来源：工程化中的“安装命令 / 安装脚本”。
- 使用场景：开发者需要把 `attach` 安装到本机 PATH 目录，便于放入 shell 启动脚本或手动调用。

## 关键功能点

- 新增 `scripts/install-attach.sh`。
- 默认 release 构建并安装到 `~/.local/bin/attach`。
- 可通过 `ATTACH_INSTALL_DIR` 覆盖安装目录。
- 可通过 `ATTACH_BUILD_PROFILE=debug` 使用 debug 构建。

## 设计与实现

- 涉及模块：`scripts/install-attach.sh`、`README.md`。
- 核心流程：cargo build → 创建目标目录 → `install -m 0755` 复制二进制。
- 重要约束：当前只是本机安装脚本，不是发布包或版本管理。

## 验证方式

- 命令：`ATTACH_INSTALL_DIR="$(mktemp -d)" ATTACH_BUILD_PROFILE=debug scripts/install-attach.sh`
- 结果：脚本成功执行，临时目录下生成可执行 `attach`。

## 后续注意事项

- 后续发布包需要独立设计版本号、签名和平台产物。
