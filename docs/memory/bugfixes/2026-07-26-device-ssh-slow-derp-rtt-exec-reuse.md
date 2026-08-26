# BugFix 记忆：真机 SSH 连接慢（5s+）与导航页慢（10s+）

## 现象

- 触发条件：真机（HUAWEI Pura 70）经 Tailscale 连接 Mac 的 SSH 终端；模拟器（127.0.0.1）无此问题。
- 用户影响：连接终端约 5~7 秒；连接成功后进入导航页（muxmirror 列表）再等约 10 秒。

## 根因

- 手机与 Mac 的 Tailscale 未打通直连，流量绕美国旧金山 DERP 中继（`tailscale status` 显示 `relay "sfo"`，`tailscale ping` 实测 333~449ms RTT）。SSH 建连是串行多轮往返（TCP/KEX/认证/channel/pty/shell），每轮付一次 RTT，合计 4~6s。带宽（142Mbps）与此无关。
- 导航页 exec（`muxmirror -format json --mux`）此前每次独立建立完整 SSH 连接（`exec_inner` → `establish_connection`），把建连成本原样再付一次；UI 层失败重试还会叠加。
- 排除项：DNS（配置为 IP 字面量，解析 15µs）；password 认证回退 kbdint（日志无回退标记，password 一次通过）；MuxServer 命令本身（<1s）。

## 修复方案

- 涉及模块：`MobileApp/shared/src/session/mod.rs`。
- 关键改动：
  - `SessionCmd` 新增 `Exec { command, reply }` 变体；会话线程收到后临时 `set_blocking(true)` 跑 `exec_on_session`，再恢复非阻塞（channel 与 `set_blocking` 均为 sess 不可变借用，可共存）。
  - `SessionHandle` 记录 host/port/username；`find_reusable_session` 匹配同服务器最新会话。
  - 新增 `exec_with_reuse`：优先复用（30s 应答超时），无会话/超时回退独立建连，保证导航页总能出结果。
  - 原 exec 读通道逻辑抽为 `exec_on_session`，独立建连路径（`exec_inner`）与复用路径共用。
  - `establish_connection` 增加分段计时日志（地址解析/TCP/握手/认证），便于后续定位。

## 验证方式

- 复现步骤：真机连接服务器 → 点 MUX 进导航页。
- 验证命令：读设备日志 `hdc -t <id> shell cat .../logs/TermMirror-YYYY-MM-DD.log`，观察 `复用会话 N 通道` 与 exec 起止时间。
- 验证结果：exec 从 4.7~8.3s 降至 ~1.5s（2026-07-26 21:05 实测，日志含「复用会话 2 通道」）；`cargo test --lib session` 10 项全过（含新增 `exec复用匹配同服务器最新会话`）。

## 预防措施

- 真机排查网络类"慢"先测 RTT 而非带宽：`tailscale status`/`tailscale ping` 看是否走 DERP relay；分段计时日志已常驻，先看 `连接计时` 再猜。
- 高 RTT 链路下严禁为一次性命令重复建连；新增远程操作一律复用已有 transport 开 channel。
- 后续优化方向：同 Wi-Fi 时优先局域网 IP（sshd 已放行 192.168.0.0/24）；连接成功后后台预热 muxmirror 查询。
- 已知关联坑：`/etc/ssh/sshd_config` 多行 `AllowUsers` 只有第一行生效（OpenSSH first-match-wins），本次未踩但随时会踩。
