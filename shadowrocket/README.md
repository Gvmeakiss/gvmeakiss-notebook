# Shadowrocket 通用分流配置

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
- `block-quic = all-proxy`：仅对走代理的连接屏蔽 QUIC / HTTP3，强制回退到 TCP 上的 HTTP/2，显著改善 SSE 长连接（流式对话类应用）经代理时的断流重连问题。

### 4. 分流规则分层（每日更新）
- 规则集采用 `blackmatrix7/ios_rule_script` 体系，经 jsDelivr CDN 加速分发，国内可达性经实测优于直连 GitHub；
- 分层：局域网直连 → 去广告 → AI 服务 → 流媒体 → 社交通讯 → 支付购物 → 游戏 → 开发云服务 → Apple 直连 → 国内服务直连 → 大类兜底；
- 规则集由上游每日自动更新，本地零维护。

### 5. 本地保底
- `GEOIP,CN → DIRECT` + `FINAL → PROXY` 兜底，即使远程规则集全部不可达，仍能正确分流，不依赖任何外部资源即可工作。

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

## 目录

- [shadowrocket-optimized.conf](./shadowrocket-optimized.conf)
