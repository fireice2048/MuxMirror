# 功能记忆：发布包脚本

## 背景

- 需求来源：工程化中的“发布包 / 版本管理”。
- 使用场景：开发者需要生成可分发的 PC 端 `attach` 二进制压缩包。

## 关键功能点

- 新增 `scripts/package-attach.sh`。
- release 构建 `attach`。
- 输出 `dist/attach-<version>-<platform>.tar.gz`。
- 包内包含 `attach` 和 `README.md`。

## 设计与实现

- 涉及模块：`scripts/package-attach.sh`、`README.md`。
- 核心流程：读取 Cargo 包版本 → release build → 复制二进制和 README → tar.gz 打包。
- 重要约束：当前是本机平台包，不做签名、多平台交叉编译或自动上传。

## 验证方式

- 命令：`ATTACH_DIST_DIR="$(mktemp -d)" scripts/package-attach.sh`
- 结果：脚本成功输出 `.tar.gz`，包内包含二进制和 README。

## 后续注意事项

- 正式发布需要增加签名、校验和、变更日志和多平台产物。
