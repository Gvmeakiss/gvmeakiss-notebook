# Shadowrocket 通用分流配置 v5

一份面向 **订阅制节点、手动切换** 场景的通用优化配置，iOS / iPadOS / macOS（Catalyst）三端通用。v5 在保留 v4 全部 AI、流媒体、社交、游戏、开发服务与去广告能力的基础上，针对 iPhone 国内 App 卡顿补充分流优先级。

## v5：移动优先双端增强

- 微信、知乎、抖音、番茄小说（含 `fanqienovel`、`fqnovel` 图文/视频域名）、DeepSeek 置于广告规则之前并强制 `DIRECT`；
- 新增支付宝、云闪付及工行、农行、中行、交行、建行、招行、邮储、平安、光大、广发等金融规则的置顶直连；
- 保留 v4 的全部海外服务规则，并补充 Twitch、Pixiv 两个书签中的常用服务；
- 保留 v4 已验证的 Quantumult X 宽覆盖 Apple/China/Global/WeChat 规则，同时用 Shadowrocket 原生细分规则补充移动 App、金融和书签服务；
- 企业、路由器或其他个人专有域名应只在**本地副本**补充 `DIRECT`，不得提交到公开仓库；
- 不添加 MITM 或 HTTPS 解密；金融 App、微信等敏感应用不应使用这类功能。

> 关键前提：导入后，在 Shadowrocket 首页将「全局路由」设为「**配置**」。若设为「代理」，所有 `DIRECT` / `PROXY` 分流规则都会被全局代理覆盖。

## 功能优化对照

| 使用场景 | v5 的处理 | 预期改善 |
|---|---|---|
| 微信、抖音、知乎、番茄小说 | 细分规则及番茄图文/视频 CDN 置于广告和大类规则之前，优先 `DIRECT` | 减少代理中转、跨境等待和登录/内容预取卡顿 |
| 银行、支付宝、云闪付 | 常见金融规则置顶 `DIRECT`，不做 HTTPS 解密 | 保留银行 App 的证书校验、生物识别和风控链路 |
| 国内网页与国内 CDN | 保留 v4 的宽覆盖 China 规则，并补充 Shadowrocket 原生 China 规则 | 不因精简规则导致 Mac 端原有国内站点改走代理 |
| ChatGPT、Gemini、Google、GitHub | 保留原有显式 `PROXY` 规则 | Mac 与 iPhone 访问海外服务时继续使用当前节点 |
| YouTube、Netflix、Twitch、Pixiv 等 | 流媒体/内容服务显式 `PROXY` | 与国内 App 直连策略互不干扰 |
| 蜂窝网络 DNS | `dns-direct-fallback-proxy = false`，直连解析失败不跨境重试 | 避免国内 App 在 DNS 回退时额外等待 |
| 长连接与流式响应 | `block-quic = all-proxy`，仅代理流量回落 TCP/HTTP2 | 降低代理侧 QUIC/HTTP3 断流和重连概率 |
| 局域网、路由器、Apple 系统服务 | 私网、回环、Apple 网段和系统域名直连 | 保持 AirPlay、局域网发现、推送和路由器管理可用 |

这份配置是“补充优化”，不是只面向手机的精简版：v4 的宽覆盖规则仍在，新增细分规则只负责提高移动端命中优先级。

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
- 分层：局域网直连 → 移动核心 App 直连 → 支付/银行直连 → 原有国内服务直连 → 去广告 → AI 服务 → 流媒体 → 社交通讯 → 支付购物 → 游戏 → 开发云服务 → Apple/TikTok → 大类兜底；
- 规则集由上游每日自动更新，本地零维护。

### 5. 本地保底
- `GEOIP,CN → DIRECT` + `FINAL → PROXY` 兜底，即使远程规则集全部不可达，仍能正确分流，不依赖任何外部资源即可工作。

## 使用

1. Shadowrocket →「配置」→ 右上角 `+` → 从文件导入本 `.conf`；
2. 首页「全局路由」选择「配置」，然后启用并断开重连一次；
3. 依次测试微信、银行/支付、抖音、知乎、番茄小说与常用海外服务；
4. 若某 App 异常，在 Shadowrocket 日志确认命中策略：`REJECT` 通常为广告规则误伤，临时注释 `[Rule]` 中 `Advertising` 那一行后重试；`PROXY` 则为该 App 仍需补充 `DIRECT` 规则。

## 参数速览

| 参数 | 值 | 作用 |
|---|---|---|
| `dns-server` | doh.pub + alidns + 223.5.5.5 + 119.29.29.29 | DNS 防污染 |
| `hijack-dns` | 8.8.8.8:53, 8.8.4.4:53 | 防硬编码 DNS 绕过 |
| `block-quic` | all-proxy | 代理流量禁 QUIC，稳长连接 |
| `ipv6` / `prefer-ipv6` | true / false | 支持 IPv6 节点但不优先 |
| `dns-direct-fallback-proxy` | false | 直连解析失败不经代理重试，优先保证国内 App/金融访问路径 |

## 本地私有覆盖（不提交 Git）

如需让企业桌面云、内部 DNS、家用 NAS 或特定路由器域名始终直连，请复制本配置到本地后，在第 4 层末尾加入规则，例如：

```ini
DOMAIN-SUFFIX,example.internal,DIRECT
```

请勿将真实企业域名、内网地址、节点订阅链接、账号或密钥推送到此公开仓库。

## 目录

- [shadowrocket-optimized.conf](./shadowrocket-optimized.conf)
