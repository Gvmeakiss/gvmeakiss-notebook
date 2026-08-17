# Shadowrocket 通用分流配置 v5

一份面向 **订阅制节点、手动切换** 场景的通用优化配置，iOS / iPadOS / macOS（Catalyst）三端通用。

## 设计要点

### 1. 配置与节点完全解耦
- 规则目标仅使用 `PROXY` / `DIRECT` / `REJECT` 三种策略，`PROXY` 始终指向「当前启用的节点」；
- 节点来自订阅、随时增删更新，本配置无需任何改动，节点切到哪，代理流量就跟到哪。

### 2. DNS 防污染（三级兜底）
- 腾讯 / 阿里 DoH 优先，普通国内 DNS 补充，系统 DNS 最后兜底；
- `hijack-dns` 仅劫持硬编码 Google DNS 请求，避免 `*:53` 全量劫持干扰局域网设备发现；
- `dns-direct-fallback-proxy` 在直连解析失败时自动回退代理，规避「能解析但被投毒」的场景。

### 3. 长连接稳定性
- `block-quic = all-proxy`：仅对走代理的连接屏蔽 QUIC / HTTP3，令相关请求回退到 TCP；可减少部分节点 UDP / 443 不稳定导致的流式连接中断；
- 该参数不能修复节点出口 IP 被 OpenAI / Cloudflare 拒绝的问题。若 Codex / ChatGPT 仍需反复重连，应优先更换美国节点，而不是增加 Google URL Rewrite。

### 4. 分流规则分层（每日更新）
- 规则集采用 `blackmatrix7/ios_rule_script` 体系，经 jsDelivr CDN 加速分发，国内可达性经实测优于直连 GitHub；
- 分层：局域网直连 → 去广告 → AI 服务 → 流媒体 → 社交通讯 → 支付购物 → 游戏 → 开发云服务 → Apple 直连 → 国内服务直连 → 大类兜底；
- 规则集由上游每日自动更新，本地零维护。

### 5. 本地保底
- `GEOIP,CN → DIRECT` + `FINAL → PROXY` 兜底，即使远程规则集全部不可达，仍能正确分流，不依赖任何外部资源即可工作。

### 6. 出差与局域网兼容
- 保留系统 DNS 最终兜底，优先保证机场、酒店和认证门户可用；
- IPv6 保持启用但不优先，并排除 ULA、链路本地和组播网段，兼容 Bonjour、AirPlay 与局域网设备；
- Apple / iCloud 直连域名使用当前网络的系统 DNS，避免境外出差时被调度到不合适的 CDN；
- `100.64.0.0/10` 默认排除以兼容运营商 CGNAT；若同时使用 Tailscale，应从 `tun-excluded-routes` 删除该网段。

## 节点选择与 Codex / ChatGPT 排查

本配置不内置节点，也不自动按地区选线。订阅更新后先测速，再手动选择当前用途对应的节点：

- Codex / ChatGPT / Gemini：优先选择实际可访问 OpenAI 服务的美国节点；
- 视频和日常娱乐：可选择延迟更低的新加坡或台湾节点；
- 延迟低不代表出口信誉良好。若三个 OpenAI 站点同时返回 HTTP 403，说明该节点出口更可能被网络层拒绝，应换节点。

可以在 macOS 终端执行以下无凭据测试：

```bash
curl -L -sS -o /dev/null -w 'HTTP %{http_code}\n' https://api.openai.com/v1/models
curl -L -sS -o /dev/null -w 'HTTP %{http_code}\n' https://chatgpt.com/
curl -L -sS -o /dev/null -w 'HTTP %{http_code}\n' https://developers.openai.com/
```

API 返回未认证响应表示已经到达 OpenAI；如果三项统一返回 Cloudflare / VPN 相关的 403，切换节点通常比反复重连更有效。

## 使用

1. Shadowrocket →「配置」→ 右上角 `+` → 从文件导入本 `.conf`；
2. 启用后断开重连一次；
3. 若某 App 被去广告规则误伤，删除 `[Rule]` 中 `Advertising` 那一行即可。

## 参数速览

| 参数 | 值 | 作用 |
|---|---|---|
| `dns-server` | doh.pub + alidns + 223.5.5.5 + 119.29.29.29 | DNS 防污染 |
| `hijack-dns` | 8.8.8.8:53, 8.8.4.4:53 | 防硬编码 DNS 绕过 |
| `block-quic` | all-proxy | 代理流量禁 QUIC，稳长连接 |
| `ipv6` / `prefer-ipv6` | true / false | 支持 IPv6 节点但不优先 |
| `dns-direct-fallback-proxy` | true | 直连解析失败回退代理 |
| `tun-excluded-routes` | IPv4 私网 + IPv6 本地网段 | 保留局域网、认证门户和设备发现 |
| `*.apple.com` / `*.icloud.com` | `server:system` | Apple 直连使用所在地 DNS / CDN |

## v5 更新

- 删除已废弃的 `bypass-system`；
- 补充 `fc00::/7`、`fe80::/10`、`ff00::/8` IPv6 本地路由排除；
- Apple、WeChat、China、Global 全部切换为 Shadowrocket 原生规则格式；
- 大类兜底改为 China 直连优先、Global 代理随后；
- PayPal 改为直连，减少共享代理出口触发账户安全验证；
- 删除与 Codex / ChatGPT 无关、且在未启用 HTTPS 解密时不能完整工作的 Google URL Rewrite；
- 保留 `block-quic = all-proxy`、`GEOIP,CN,DIRECT` 和 `FINAL,PROXY`。

## 目录

- [shadowrocket-optimized.conf](./shadowrocket-optimized.conf)
