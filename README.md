# MuxMirror

MuxMirror 是一个远程终端工具：手机 App 通过 SSH 直连电脑，远程查看和操作电脑上的终端窗口/标签页。无需改变终端使用习惯，直接呈现 PC 上已有的终端会话，手机端即开即用。

- `MirrorServer/`：电脑端 CLI（macOS），负责终端窗口枚举、画面同步、输入转发。
- `MobileApp/`：手机端 App，支持 HarmonyOS / Android / iOS。

## 一、电脑端安装（macOS）

前置要求：Rust 工具链（cargo）、Xcode Command Line Tools（swiftc）。

```sh
scripts/install-muxmirror.sh
```

安装程序会构建并安装：

- 主程序：`~/.termimirror/bin/muxmirror`
- 辅助功能 Helper：`~/.termimirror/libexec/muxmirror/muxmirror-ax-helper`

安装结束后会主动请求 macOS 辅助功能权限并打开「系统设置 → 隐私与安全性 → 辅助功能」，请允许显示的 MuxMirror/SSH 相关条目（通常是 `sshd-keygen-wrapper`）。完成后复检：

```sh
~/.termimirror/bin/muxmirror doctor
```

注意：

- 建议把 `~/.termimirror/bin` 加入 `PATH`。
- 安装过程中 `setup`/`doctor` 会通过 `localhost` SSH 自检，可能要求输入本机密码，属正常现象。
- 窗口扫描依赖辅助功能权限；权限未授予时会提示重新执行 `muxmirror setup`。

## 二、电脑端 tmux 配置（推荐）

为配合手机端远程操作，建议电脑端 Apple Terminal 配置「开终端自动进 tmux、新标签页继承当前路径、关标签页自动清理会话」。

### `~/.tmux.conf`

```tmux
set -g history-limit 5000
set -g mouse off
set -g set-clipboard on
# 允许 pane 内 OSC 7（cwd 上报）透传给外层终端，使新建标签页继承 tmux 内最新路径
set -g allow-passthrough on
# 手动 detach 时保留会话，并让 tmux client 原地切回登录 zsh
bind-key d set-option destroy-unattached off \; detach-client -E 'TERMHOOK_TMUX_DETACHED=1 exec zsh -l'
```

### `~/.zshrc` 追加

```sh
# ── 每个标签页自动启动独立 tmux 会话 ──
start_tmux_once() {
    # 已在 tmux/rmux 里不重入
    [ -n "$TMUX" ] || [ -n "$RMUX_SESSION" ] || [ -n "$RMUX" ] && return 0
    [ -n "$TERMHOOK_TMUX_DETACHED" ] && return 0
    # SSH 远程会话（手机端）不自动启动 tmux——由手机端自行 attach 目标会话
    [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ] && return 0
    command -v tmux &>/dev/null || { echo "警告: tmux 未安装"; return 1; }

    local session_name next_id=1 attempt=0

    while IFS= read -r session_name; do
        [[ "$session_name" == tmux_<-> ]] || continue
        local num="${session_name#tmux_}"
        (( num >= next_id )) && next_id=$((num + 1))
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

    while (( attempt < 20 )); do
        session_name="tmux_${next_id}"
        # 先原子创建 detached 会话，避免并发新建标签页时撞号。
        if tmux new-session -d -s "$session_name" -c "$PWD"; then
            tmux set-hook -t "$session_name" client-attached \
                'set-option destroy-unattached on'
            # 用 tmux client 替换登录 zsh，避免 Terminal 等待前台子进程超时。
            exec tmux attach-session -t "=$session_name"
            return 1
        fi
        tmux has-session -t "=$session_name" 2>/dev/null || return 1
        next_id=$((next_id + 1))
        attempt=$((attempt + 1))
    done
    return 1
}

# ── tmux 内 cwd 上报（OSC 7）经 DCS passthrough 透传给 Apple Terminal ──
_tmux_passthrough_cwd_setup() {
    [[ -z "${TMUX:-}" ]] && return
    (( $+functions[update_terminal_cwd] )) || source /etc/zshrc_Apple_Terminal 2>/dev/null
    (( $+functions[update_terminal_cwd] )) || return
    _tmux_passthrough_terminal_cwd() {
        local seq esc=$'\e'
        seq=$(update_terminal_cwd)
        [[ -n "$seq" ]] && printf '\ePtmux;%s\e\\' "${seq//$esc/$esc$esc}"
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _tmux_passthrough_terminal_cwd
}

start_tmux_once
unset TERMHOOK_TMUX_DETACHED
_tmux_passthrough_cwd_setup
```

## 三、手机端 App 构建与安装

### HarmonyOS

前置要求：DevEco Studio 命令行工具（devecocli）、hdc、OHOS Rust target。

```sh
./scripts/deploy-harmony.sh sim     # 部署到模拟器
./scripts/deploy-harmony.sh device  # 部署到真机
./scripts/deploy-harmony.sh all     # 模拟器 + 真机
```

脚本会完成 Rust 核心交叉编译、`.so` 拷贝、HAP 构建、安装并启动。

### Android / iOS

```sh
./scripts/deploy-mobile.sh android  # Android 模拟器
./scripts/deploy-mobile.sh ios      # iOS 模拟器（iPhone 17 Pro）
./scripts/deploy-mobile.sh all      # 两端
```

也可手动分步构建：先构建 Rust 核心，再编译原生工程。

```sh
cd MobileApp/shared
bash scripts/build-ohos.sh     # 鸿蒙
bash scripts/build-android.sh  # Android
bash scripts/build-ios.sh      # iOS
```

## 四、使用注意事项

- **网络**：手机与电脑需网络互通；手机端通过标准 SSH 连接电脑，请先在 macOS「系统设置 → 共享」中开启「远程登录」。
- **认证**：当前仅支持 IPv4 + 密码认证，公钥认证待补齐。
- **macOS sshd 源地址限制**：若 `/etc/ssh/sshd_config` 配置了 `AllowUsers user@<网段>`，需包含手机所在网段；鸿蒙模拟器连接时来源为 `127.0.0.1`，需额外放行 `127.0.0.0/8`，否则密码正确也会认证失败。排查详见 `docs/memory/feedback/2026-07-17-ssh-allowusers-source-restriction.md`。
- **软键盘交互**：移动端内置双行工具条，支持常用符号、方向键、翻页、Ctrl/Alt 锁定、安全粘贴；全屏 TUI（如 Codex）下支持双指纵向滑动回看历史。
- **画面同步限制**：macOS 上 Terminal.app 的画面读取与输入转发基于 AppleScript，受权限和轮询延迟限制；输入转发在无辅助功能权限时会降级为 `do script`（会污染 shell 历史）。Linux 下输入转发可用，画面读取受限。

## 当前平台支持

| 平台 | 状态 |
|------|------|
| 电脑端 macOS | 可用（Terminal.app / iTerm2） |
| 电脑端 Linux | 部分可用（画面读取受限） |
| 电脑端 Windows | 仅 managed PTY（Windows 10 1809+） |
| 手机端 HarmonyOS | 可用 |
| 手机端 Android / iOS | 主要功能已就绪，细节打磨中 |
