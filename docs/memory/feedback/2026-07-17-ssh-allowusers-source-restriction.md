# 反馈记忆：sshd `AllowUsers` 源地址限制导致模拟器 SSH 认证假"密码错误"

## 坑点描述

macOS `/etc/ssh/sshd_config` 存在 `AllowUsers medie@100.0.0.0/8 medie@192.168.0.0/24`（仅允许 Tailscale 与家庭网段来源）时，鸿蒙模拟器经 `10.0.2.2`（QEMU 宿主机别名）连接本机 SSH，**sshd 看到的来源地址是 `127.0.0.1`**，不在允许范围内，认证必被拒。客户端表现为 libssh2 `-18`（与密码错误完全相同的报错），极具误导性。

## 现象与证据

- 模拟器 App：TCP 连接、SSH 握手全部成功，password 与 keyboard-interactive 两种方式均返回 `-18`。
- 本机终端 `ssh medie@127.0.0.1`：`Connection closed by 127.0.0.1 port 22`，连密码提示都不出现（同属来源被拒）。
- 真机其他 SSH App 用同一账号密码可以正常登录（其来源在允许网段内）。
- 逐字节核对 App 保存的密码（4 位纯数字、全 ASCII、无全角/空白），与真实密码完全一致，仍失败。

## 根因

- `AllowUsers user@<网段>` 按**来源 IP** 限制登录，认证请求无论凭据对错一律拒绝。
- 模拟器 NAT 出口即宿主机回环：guest → `10.0.2.2:22` ≡ 本机 `127.0.0.1:22`。
- 与 2026-07-16 的坑叠加：当日报 `-18` 是保存的密码确实错误（OpenDirectory 记录 `authtok is incorrect`）；本次密码改正后仍 `-18`，根因已切换为来源限制。同一报错两种根因，排查时必须重新定性。

## 排查方法（按顺序）

1. 对照测试：`ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no <用户>@127.0.0.1`，输入同一密码。失败 → 服务端限制（优先查 `AllowUsers`、`Match` 段），成功 → 才怀疑客户端。
2. 查 `/etc/ssh/sshd_config` 及 `/etc/ssh/sshd_config.d/*` 的 `AllowUsers`/`DenyUsers`/`Match`。
3. 不要只凭 `-18` 就认定密码错误；也不要被"真机能连"误导——先确认真机连接的**来源网段**是否在允许列表内。

## 解法

```sh
echo 'AllowUsers medie@127.0.0.0/8 medie@172.20.10.0/28' | sudo tee -a /etc/ssh/sshd_config
```

- 追加即可，多条 `AllowUsers` 累计生效，无需改动原有限制。
- sshd 每次连接都会重读配置，无需重启服务。
- `127.0.0.0/8` 覆盖模拟器回环路径（长期保留）；`172.20.10.0/28` 为热点临时网段（按需要保留或删除）。

## 验证方式

- 2026-07-17：追加规则后模拟器重连，密码认证通过，PTY shell 出现远端提示符（`Last login: ...` + shell 提示符截图留存）。
- 本机 `ssh medie@127.0.0.1` 同步恢复可登录。

## 预防

- 模拟器 SSH 验收前，先跑上面的回环对照测试确认服务端无来源限制。
- 验收文档与 AGENTS.md 已记录该环境前提（`AGENTS.md` → "鸿蒙模拟器 SSH 联调环境要求"）。
