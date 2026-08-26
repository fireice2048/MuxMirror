# 决策：分离 Attach 服务连接与监听地址

## 背景

移动端需要经局域网访问电脑端服务，而 Attach CLI 自身应继续通过本机回环地址访问服务。把某台电脑的网卡 IP 直接写入 `service_addr` 会导致换网络或换电脑后失效。

## 决策

- `service_addr` / `ATTACH_SERVICE_ADDR` 仅表示 Attach CLI 连接服务的地址。
- `listen_addr` / `ATTACH_LISTEN_ADDR` 仅表示服务进程绑定的地址。
- 未设置 `listen_addr` 时沿用 `service_addr`，兼容既有本机使用方式。
- 局域网部署配置为 `service_addr=127.0.0.1:<port>`、`listen_addr=0.0.0.0:<port>`；移动端使用当前电脑实际局域网 IP 与该端口。

## 影响与验证

- 不再需要在服务端配置具体网卡 IP。
- `cargo test -p attach --bin attach` 覆盖环境变量和配置文件选择逻辑。
- managed PTY CLI 集成流程继续通过。
