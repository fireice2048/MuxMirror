# muxmirror 安装期辅助功能权限验收

## 自动化预检

- [x] Rust 单元测试通过。
- [x] Swift AX Helper 可独立编译。
- [x] 临时前缀安装生成主程序和稳定 Helper。
- [x] `doctor` 可调用指定 Helper 检查权限。
- [x] 正常构建和检查未生成 `/tmp/term_enum_helper_v13`。
- [x] localhost SSH 命令仅尝试密码认证，不会因 SSH Agent 公钥过多提前失败。
- [x] 本机窗口扫描通过 localhost SSH 调用 Helper；已有 SSH 会话直接调用，
  两条路径不会递归连接。

## 用户现场验收

旧安装和旧 Helper 清理完成后，由用户在仓库根目录亲自执行：

```sh
scripts/install-muxmirror.sh
```

验收步骤：

1. 安装程序显示主程序与 Helper 的稳定安装路径。
2. 安装程序通过 localhost SSH 检查远端权限，必要时要求输入本机 SSH 密码。
3. macOS 弹出辅助功能权限提醒并打开对应系统设置。
4. 在辅助功能列表中允许新出现的 MuxMirror/SSH 相关条目（通常是
   `sshd-keygen-wrapper`）。
5. 执行 `~/.local/bin/muxmirror doctor`，应显示“辅助功能权限：已授权”。
6. 执行 `~/.local/bin/muxmirror --format json`，必要时输入 localhost SSH
   密码；应返回终端窗口数据，且不再出现新的权限弹窗。本机结果应与手机
   SSH 执行结果使用同一个 `sshd-keygen-wrapper` 权限主体。
7. 手机连接服务端并进入终端页面，电脑端不应再临时弹出权限提醒。

> 如果安装程序首次请求后以未授权状态退出，这是 macOS 异步权限确认的正常过程；在系统设置中允许后，重新运行安装程序或执行 `doctor` 即可。
