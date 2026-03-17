---
title: "自建 Tailscale DERP 中继：从 900ms 到 34ms"
date: 2026-03-17
tags: ["Tailscale", "网络", "VPN", "内网穿透", "运维"]
draft: false
description: "在中国大陆搭建 Tailscale 自建 DERP 中继，绕过 ISP SNI 过滤，将局域网延迟从 900ms 压缩到 34ms 的完整记录。"
---

家里有一台 Mac Mini（广东家宽）、一台 Windows 台式机（手机热点）和一台 iPad，希望它们组成一个私有网络，随时可以互相访问。Tailscale 是目前最省心的方案——零配置、自动穿透 NAT、跨平台——但它有一个致命问题：**默认的 DERP 中继服务器在多伦多**，中国用户延迟 500-900ms，基本不可用。

这篇文章记录整个优化过程：从发现问题、选方案、踩坑、到最终 **34ms** 的完整经历。

## 为什么需要 DERP 中继

Tailscale 优先建立 P2P 直连（WireGuard），但 P2P 并非总能成功：

- **双端都在 NAT 后**：需要 STUN 打洞，失败率较高
- **一端是 CGNAT**（运营商级 NAT）：无法直连，必须中继
- **防火墙限制**：某些网络封锁 UDP

我的 Mac 在移动家宽下，没有公网 IP、没有 IPv6，是典型的 CGNAT 场景。Tailscale 回退到 DERP 中继转发所有流量，默认就走多伦多节点。

## 方案：在阿里云深圳自建 DERP

既然两端都在广东，最优方案是在华南找一台低延迟服务器。阿里云深圳的 ECS ping 约 10ms，理论中继延迟 ≈ 10ms × 2 = 20ms，加上两端各自的网络抖动，实测约 **34ms**。

架构如下：

![网络拓扑](/images/tailscale/network-topology.svg)

## 第一个大坑：ISP SNI 过滤

按照常规操作，在服务器上部署 `derper`，申请 Let's Encrypt 证书，配置域名 `example.com`，然后在 Tailscale ACL 的 `derpMap` 里填上这个地址。

结果：**完全无法连接**。

诊断时发现一个规律：

```bash
# HTTP 正常，返回 400（连接到达服务器）
curl http://example.com:443/
# → HTTP 400

# TLS 无 SNI，返回错误（但 TLS 握手到达服务器）
curl -k https://YOUR_SERVER_IP:443/
# → tlsv1 alert internal error

# TLS 带域名 SNI，0 字节响应
curl https://example.com:443/
# → SSL_ERROR_SYSCALL（连接被直接丢弃）
```

规律很清晰：**只要 TLS Client Hello 里包含 `example.com` 这个 SNI 字段，运营商就丢包**。中国电信/移动对国内 IP 做深度包检测（DPI），未备案域名的 TLS 会被 SNI 识别并过滤。

这意味着：不管什么端口（443、8443 都没用），只要 TLS 握手里有未备案域名，就会被封。

![ISP SNI 过滤原理](/images/tailscale/sni-filtering.svg)

## 解决方案：IP 自签证书

突破口是：**如果 TLS Client Hello 里没有 SNI（即用 IP 地址直连而非域名），ISP 就无法识别并过滤**。

生成一张以 IP 地址为主体的自签证书：

```bash
openssl req -x509 \
  -newkey ec \
  -pkeyopt ec_paramgen_curve:prime256v1 \
  -nodes \
  -keyout /etc/derper/certs/YOUR_SERVER_IP.key \
  -out /etc/derper/certs/YOUR_SERVER_IP.crt \
  -days 3650 \
  -subj "/CN=YOUR_SERVER_IP" \
  -addext "subjectAltName=IP:YOUR_SERVER_IP"
```

然后以 IP 作为 hostname 启动 derper，使用 manual 证书模式：

```bash
derper \
  -hostname YOUR_SERVER_IP \
  -a :8443 \
  -http-port -1 \
  -stun-port 3478 \
  -certmode=manual \
  -certdir=/etc/derper/certs \
  -verify-clients=false
```

`-hostname` 为 IP 地址时，客户端建立 TLS 连接时填的 ServerName 是 IP 而非域名，TLS Client Hello **不会携带 SNI 字段**，运营商的 DPI 看不到任何域名，直接放行。

## derper systemd 服务配置

```ini
# /etc/systemd/system/derper.service
[Unit]
Description=Tailscale DERP Server
After=network.target

[Service]
ExecStart=/root/go/bin/derper \
  -hostname YOUR_SERVER_IP \
  -a :8443 \
  -http-port -1 \
  -stun-port 3478 \
  -certmode=manual \
  -certdir=/etc/derper/certs \
  -verify-clients=false
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now derper
```

注意开放安全组：**TCP 8443**（DERP）和 **UDP 3478**（STUN）。

## Tailscale ACL derpMap 配置

derper 启动后，日志里会打印自签证书的 SHA-256 哈希，用这个哈希在 ACL 里做证书 pin：

```json
"derpMap": {
  "OmitDefaultRegions": true,
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "aliyun-sz",
      "RegionName": "Aliyun Shenzhen",
      "Nodes": [{
        "Name": "sz1",
        "RegionID": 900,
        "HostName": "YOUR_SERVER_IP",
        "CertName": "sha256-raw:<derper 启动日志中打印的哈希>",
        "DERPPort": 8443,
        "STUNPort": 3478
      }]
    }
  }
}
```

关键点：

- `OmitDefaultRegions: true`：禁用官方 DERP，强制走自建节点
- `CertName: "sha256-raw:..."`：接受自签证书（Tailscale 客户端会用此哈希验证，不走系统 CA 链）
- `"ForceHTTP"` 字段**不存在**，不要填，会报 `unknown field` 错误

## 第二个坑：Clash TUN 干扰诊断

在调试过程中，一个诡异现象让我浪费了不少时间：**所有 `nc` 端口探测都显示 "succeeded"**，包括根本没开放的端口。

原因：Mac 上开了 Clash Verge 的 TUN 模式，它在内核层拦截所有网络流量（通过虚拟网卡接口，占用一段保留 IP 段）。`nc` 连的不是真实服务器，而是 Clash 的虚拟接口。

诊断方法：

```bash
# 看路由走向
route get YOUR_SERVER_IP
# 如果 interface: utun1024，说明被 Clash TUN 拦截了
```

修复方法是在 Clash 配置里加直连规则，让 tailscaled 和 DERP IP 绕过代理：

```yaml
rules:
  - IP-CIDR,YOUR_SERVER_IP/32,🎯 Direct,no-resolve  # 阿里云 DERP
  - PROCESS-NAME,tailscaled,🎯 Direct               # tailscaled 进程
```

## 最终效果

![延迟对比](/images/tailscale/latency-chart.svg)

| 阶段 | DERP 节点 | 延迟 |
|------|-----------|------|
| 优化前 | 默认（多伦多） | 470 – 930 ms |
| 自建 HK VPS | 香港，IPv4+IPv6 | 130 – 170 ms |
| 自建阿里云 | 广东深圳 | **34 ms** |

Mac → DERP 单程 12.8ms，稳定 ±0.5ms，基本已到物理极限（两跳各 ~13ms）。

## 经验总结

1. **中国 ISP 对国内 IP 做 SNI 过滤**：只要 TLS Client Hello 有未备案域名，连接就被丢弃。HTTP 和无 SNI 的 TLS 不受影响。

2. **IP 自签证书是正确解法**：`derper -hostname <IP> -certmode=manual`，生成 IP SAN 证书，客户端用 `sha256-raw:` CertName 做哈希 pin，无需 CA 信任链。

3. **非 443 端口的 derper 默认是 HTTP**：必须显式加 `-certmode=manual` 才启用 TLS，否则在非 443 端口上 DERP 走明文 HTTP。

4. **Clash TUN 会产生假阳性**：`nc`、`curl` 等工具测试结果不可信，用 `route get <ip>` 确认实际路由。

5. **`sha256-raw:` CertName 完全可用**：之前网上很多资料说自签证书不能用，实测完全可行，这是 Tailscale 官方支持的 cert pinning 方式。

## 后续计划

目前的 34ms 是 DERP 中继的延迟，还可以进一步优化：如果 Mac 侧能获得 IPv6（中国移动光猫开启 IPv6 需要重建 PPPoE 连接），就可以实现 P2P 直连，理论延迟降到 **~12ms**（单程 ping 值）。等拿到运营商 PPPoE 密码后再试。
