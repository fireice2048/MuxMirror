# 仓库指南

## 项目结构与模块组织

本仓库使用 Rust 语言。目录结构请遵循 Cargo 约定：

- `Cargo.toml` 用于包元数据、依赖、特性和 workspace 配置。
- `MirrorServer/` 用于电脑端终端 CLI 工具开发，方向参考 tmux 的终端复用、会话管理、detach/reattach 能力。
- `MobileApp/` 用于移动端 SSH 终端 App 开发，重点支持手机软键盘交互和远程控制电脑端终端会话。架构为 Rust 核心库（`MobileApp/shared/`，cdylib）+ HarmonyOS ArkTS UI（`MobileApp/harmonyApp/`）+ NAPI FFI 桥接。**`MobileClient/`（KMP/Compose Multiplatform 方案）已删除，不再开发，禁止引用该目录。**
- `src/lib.rs` 用于库入口，`src/main.rs` 用于二进制入口。
- `tests/` 用于集成测试；单元测试应靠近被测代码，并放在 `#[cfg(test)]` 下。
- `examples/` 用于可运行示例；`fixtures/` 用于非代码测试数据。
- `docs/` 用于设计说明和贡献者文档。
- `docs/requirements/` 用于记录产品需求、使用场景、非目标和待澄清问题。
- `docs/acceptance/` 用于记录人工验收方法和通过标准。
- `docs/memory/` 用于记录开发和 BugFix 过程中的关键功能点、重点问题、技术决策和排查结论。
- `README.md` 应在开发过程中同步维护，记录项目目标、运行方式、架构概览和当前限制。

模块应保持职责单一且边界清晰。不要提交 `target/`。

## 构建、测试与开发命令

以 Cargo 作为主要入口：

- `cargo build` — 编译当前包或 workspace。
- `cargo test` — 运行单元测试、文档测试和集成测试。
- `cargo fmt --all` — 使用 `rustfmt` 格式化全部 Rust 代码。
- `cargo clippy --all-targets --all-features` — 对所有目标和特性运行 lint 检查。
- `cargo run -- <args>` — 本地运行默认二进制程序。

仅在需要封装可复用的多步骤流程时添加脚本。

### 鸿蒙 Rust 核心库构建与部署

移动端架构：Rust 核心（`MobileApp/shared/`）交叉编译为 `libtermirror_core.so`，放入 `MobileApp/harmonyApp/entry/libs/<abi>/`，由 NAPI 层（`napi_init.cpp`）桥接给 ArkTS UI。

**SSH 依赖自包含**：libssh2 + mbedTLS 的源码、构建脚本、静态库产物、pkgconfig 全部位于 `MobileApp/shared/` 内部（`third_party/`、`scripts/build-ssh-dependencies.sh`、`build/ohos-ssh/<abi>/`、`pkgconfig/`）。不依赖仓库内任何其他目录，禁止引用已删除的 `MobileClient/`。

Rust 核心变更后按以下顺序部署：

```sh
cd MobileApp/shared
# 交叉编译（真机 arm64 / 模拟器 x86_64）
cargo build --release --target aarch64-unknown-linux-ohos
cargo build --release --target x86_64-unknown-linux-ohos
# 拷贝 .so 到鸿蒙工程
cp target/aarch64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/arm64-v8a/
cp target/x86_64-unknown-linux-ohos/release/libtermirror_core.so ../harmonyApp/entry/libs/x86_64/
# 重建 HAP 并安装
cd ../harmonyApp
devecocli build clean
devecocli build --build-mode debug
hdc -t <设备地址> install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <设备地址> shell aa start -a EntryAbility -b com.attach.mobile.harmony
```

若只改 ArkTS/资源且不改 Rust 核心，可使用增量 `devecocli build`（跳过 cargo 步骤）。

#### 快捷脚本

- **`scripts/deploy-harmony.sh`**：一键完成 Rust 核心交叉编译、拷贝 `.so`、构建 HAP、安装并启动。支持模拟器、真机或同时部署。

  ```sh
  ./scripts/deploy-harmony.sh sim     # 仅模拟器（默认 Pura 90 Pro）
  ./scripts/deploy-harmony.sh device  # 仅真机（自动检测第一个 Kind=device 的设备）
  ./scripts/deploy-harmony.sh all     # 模拟器 + 真机（默认）
  ```

- **`MobileApp/shared/scripts/pkg-config-ohos.sh`**：OHOS 预编译 `libssh2` 的最小化 `pkg-config` 包装脚本（实际为 Python3）。由 `build-ohos.sh` / `build.rs` 调用，用于让 Rust 交叉编译环境找到 `libssh2` 静态库与头文件，**通常不需要手动执行**；仅在调试 SSH 依赖链接问题或验证 `.pc` 输出时使用。


验收时必须在启动稳定后截图或现场确认变更已经生效；不要仅以”构建成功”和”install bundle successfully”作为更新成功的证据。

注意安装包必须选 `entry-default-signed.hap`：同目录下的 `entry-default-unsigned.hap` 是真正的未签名包，对已签名安装做 `install -r` 会报 `error:install sign info inconsistent`；此时若改用卸载重装（`devecocli run --uninstall`），应用数据（服务器配置/凭据）会被清空。签名一致时 `install -r` 保留应用数据。

### 鸿蒙模拟器 SSH 联调环境要求

在鸿蒙模拟器验收“SSH 直连本机”前，必须先确认两个环境前提，否则会出现密码正确也连不上的假象：

1. **macOS sshd 的 `AllowUsers` 源地址限制**。模拟器连 `10.0.2.2`（QEMU 宿主机别名）时，sshd 看到的来源地址是 `127.0.0.1`。若 `/etc/ssh/sshd_config` 存在 `AllowUsers user@<网段>` 之类的限制且不含 `127.0.0.0/8`，认证必定失败（libssh2 返回 -18），与密码是否正确无关。本机 `ssh <用户>@127.0.0.1` 也会同样被拒（表现为 Connection closed、无密码提示）。解法：

   ```sh
   echo 'AllowUsers medie@127.0.0.0/8 medie@172.20.10.0/28' | sudo tee -a /etc/ssh/sshd_config
   ```

   sshd 每次连接都会重读配置，无需重启服务。排查顺序：先跑 `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <用户>@127.0.0.1` 做对照；通过则服务端无限制，失败则先查 `AllowUsers`/`Match` 段，再怀疑密码。

2. **模拟器系统镜像版本**（历史约束，仅 KMP 时代适用）。Compose Multiplatform 鸿蒙版渲染依赖 API 20+ 的 OH_Drawing 接口，API 18 模拟器会全屏白屏。当前 ArkTS 方案不受此限制。`devecocli` 找不到镜像时，检查 `~/Library/Huawei/Sdk/system-image/` 并用 `Emulator -start <名称> -imageRoot ~/Library/Huawei/Sdk/system-image` 直接启动。

详见 `docs/memory/feedback/2026-07-17-ssh-allowusers-source-restriction.md` 与 `docs/memory/feedback/2026-07-17-harmony-emulator-api18-white-screen.md`。

## 编码风格与命名约定

遵循惯用 Rust 风格和 `rustfmt` 输出。模块、函数和变量使用 `snake_case`；类型和 trait 使用 `PascalCase`；常量使用 `SCREAMING_SNAKE_CASE`。公开 API 使用 `///` 文档注释。可恢复错误优先返回 `Result<T, E>`，不要使用 panic。

## 日志规范

优先使用 `tracing` 或 `log` facade 记录结构化日志；除示例或一次性 CLI 输出外，不要用 `println!` 或 `eprintln!` 记录运行诊断信息。日志级别保持一致：`trace` 用于高频流程细节，`debug` 用于诊断信息，`info` 用于生命周期里程碑，`warn` 用于可恢复异常，`error` 用于操作失败。包含稳定上下文字段，例如请求 ID、文件路径或命令名。不要记录密钥、令牌、密码、私钥或完整个人数据。使用 `RUST_LOG` 或 feature flag 控制详细日志。

## 测试指南

新增行为或修复 bug 时应补充测试。测试名称描述预期行为，例如 `rejects_invalid_config`。测试应可重复、相互隔离；除非明确标注，否则不要依赖网络或本机环境。

## 记忆系统

开发关键功能、修复重要 bug、做出架构决策或发现重复踩坑问题时，必须更新 `docs/memory/`。重大 Bug 修复后记录现象、根因、修复方案和预防措施；典型踩坑或同类错误重复 2 次及以上时，必须记录错误模式、触发条件和正确做法。新增记录优先复制 `docs/memory/templates/` 下的模板，文件名使用 `YYYY-MM-DD-short-topic.md`。记录应包含背景、关键结论、影响范围和验证方式；不要写入密钥、令牌、密码、私钥或未脱敏日志。记忆文件应定期回顾，过期或不再适用时及时更新或删除。

## 需求文档

收到新产品需求、流程规则或重要需求变更时，必须第一时间同步更新 `docs/requirements/`，先记录再开工。需求文档应记录背景、目标、平台需求、关键流程、非目标和待澄清问题；开发实现前以需求文档作为范围依据。

## 复杂任务执行

遇到项目较复杂任务时（不是单纯修复一个 Bug，也不是简单 UI 调整），必须先把计划任务写入项目文档，并同步维护可勾选的进度文档。每完成一个小里程碑，必须提交一笔代码，commit log 使用中文。目标是上下文丢失或新模型接管时，仍能从计划文档和进度文档找到正确步骤继续执行。

## Commit 与 Pull Request 指南

commit log 使用中文，所有文档使用中文。提交信息使用简洁说明，可选 scope。

Pull Request 应包含变更摘要、测试证据、关联 issue，以及可见 CLI 行为变化对应的日志或截图。保持 PR 聚焦。

## Agent 专用说明

编辑前先检查仓库状态，避免覆盖用户改动。优先做最小、聚焦的修改。开发功能或调整架构时，同步更新 `README.md`；当项目结构、命令或日志约定变化时，同步更新本指南。
