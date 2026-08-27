# Shadowrocket 双端优化配置

一份面向 **订阅制节点、手动切换** 场景的分流配置，适用于 iOS / iPadOS / macOS（Catalyst）。配置重点是让国内移动 App 和局域网服务优先直连，让 AI、海外内容、社交及开发服务按类别走当前代理节点。

## 核心功能

- 微信、知乎、抖音、番茄小说（含图文/视频 CDN）和 DeepSeek 在广告规则之前优先 `DIRECT`；
- ChatGPT、Gemini、Google、GitHub、YouTube、Twitch、Pixiv 等海外服务按类别 `PROXY`；
- Apple 系统服务、私网、回环地址和国内常用服务 `DIRECT`；
- Quantumult X 宽规则覆盖长尾域名，Shadowrocket 原生规则提高常用服务的明确命中率；
- `GEOIP,CN → DIRECT` 与 `FINAL → PROXY` 处理未被远程规则集命中的请求；
- 路由器和本地私网由私网地址规则直接处理，无需逐个写入域名。

> 关键前提：导入后，在 Shadowrocket 首页将「全局路由」设为「**配置**」。若设为「代理」，所有 `DIRECT` / `PROXY` 分流规则都会被全局代理覆盖。

> 金融类 App 不设置专属域名规则。使用银行、支付、证券等金融 App 前，请先关闭 Shadowrocket，使用完成后再按需开启。

## 分流逻辑

| 使用场景 | 处理逻辑 | 作用 |
|---|---|---|
| 微信、抖音、知乎、番茄小说 | 细分规则及番茄图文/视频 CDN 置于广告和大类规则之前，优先 `DIRECT` | 减少代理中转、跨境等待和登录/内容预取卡顿 |
| 国内网页与国内 CDN | China 宽规则、原生 China 规则与 `GEOIP,CN` 共同直连 | 减少国内网站误走代理的延迟 |
| ChatGPT、Gemini、Google、GitHub | 显式 `PROXY` | Mac 与 iPhone 访问海外服务时使用当前节点 |
| YouTube、Netflix、Twitch、Pixiv 等 | 流媒体/内容服务显式 `PROXY` | 与国内 App 直连策略互不干扰 |
| 蜂窝网络 DNS | `dns-direct-fallback-proxy = false`，直连解析失败不跨境重试 | 避免国内 App 在 DNS 回退时额外等待 |
| 长连接与流式响应 | `block-quic = all-proxy`，仅代理流量回落 TCP/HTTP2 | 降低代理侧 QUIC/HTTP3 断流和重连概率 |
| 局域网、路由器、Apple 系统服务 | 私网、回环、Apple 网段和系统域名直连 | 保持 AirPlay、局域网发现、推送和路由器管理可用 |

## 设计要点

### 1. 配置与节点完全解耦
- 规则目标仅使用 `PROXY` / `DIRECT` / `REJECT` 三种策略，`PROXY` 始终指向「当前启用的节点」；
- 节点来自订阅、随时增删更新，本配置无需任何改动，节点切到哪，代理流量就跟到哪。

### 2. DNS 防污染与移动端回退控制
- 腾讯 / 阿里 DoH 优先，普通国内 DNS 补充，系统 DNS 最后兜底；
- `hijack-dns` 仅劫持硬编码 Google DNS 请求，避免 `*:53` 全量劫持干扰局域网设备发现；
- `dns-direct-fallback-proxy = false`：直连域名解析失败不经代理重试，减少 iPhone 蜂窝网络下国内 App 的回退等待和跨境解析路径。

### 3. 长连接稳定性
- `block-quic = all-proxy`：仅对走代理的连接屏蔽 QUIC / HTTP3，强制回退到 TCP 上的 HTTP/2，显著改善 SSE 长连接（流式对话类应用）经代理时的断流重连问题。

### 4. 分流规则分层（每日更新）
- 规则集采用 `blackmatrix7/ios_rule_script` 体系，经 jsDelivr CDN 加速分发，国内可达性经实测优于直连 GitHub；
- 分层：局域网直连 → 移动核心 App 直连 → 国内常用服务直连 → 去广告 → AI 服务 → 流媒体 → 社交通讯 → 购物 → 游戏 → 开发云服务 → Apple/TikTok → 大类域名规则 → 本地保底；
- 规则集由上游每日自动更新，本地零维护。

### 5. 本地保底
- `GEOIP,CN → DIRECT` + `FINAL → PROXY` 兜底，即使远程规则集全部不可达，仍能正确分流，不依赖任何外部资源即可工作。

## 使用

1. Shadowrocket →「配置」→ 右上角 `+` → 从文件导入本 `.conf`；
2. 首页「全局路由」选择「配置」，然后启用并断开重连一次；
3. 依次测试微信、抖音、知乎、番茄小说与常用海外服务；金融类 App 请关闭 Shadowrocket 后使用；
4. 若某 App 异常，在 Shadowrocket 日志确认命中策略：`REJECT` 通常为广告规则误伤，临时注释 `[Rule]` 中 `Advertising` 那一行后重试；`PROXY` 则为该 App 仍需补充 `DIRECT` 规则。

## 参数速览

| 参数 | 值 | 作用 |
|---|---|---|
| `dns-server` | doh.pub + alidns + 223.5.5.5 + 119.29.29.29 | DNS 防污染 |
| `hijack-dns` | 8.8.8.8:53, 8.8.4.4:53 | 防硬编码 DNS 绕过 |
| `block-quic` | all-proxy | 代理流量禁 QUIC，稳长连接 |
| `ipv6` / `prefer-ipv6` | true / false | 支持 IPv6 节点但不优先 |
| `dns-direct-fallback-proxy` | false | 直连解析失败不经代理重试，优先保证国内 App 的访问路径 |

## 自定义域名

如需让家用 NAS 或其他私有域名始终直连，可在第 3 层末尾添加规则，例如：

```ini
DOMAIN-SUFFIX,example.internal,DIRECT
```

请勿将真实企业域名、内网地址、节点订阅链接、账号或密钥推送到此公开仓库。

## 目录

- [shadowrocket-optimized.conf](./shadowrocket-optimized.conf)
