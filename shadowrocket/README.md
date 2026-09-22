# Shadowrocket Mac / iPhone 通用分流配置

更新日期：2026-09-23。

面向「家庭梅林代理 + 外出大陆热点或蜂窝网络」的同一份分流配置。Mac 与 iPhone 分别导入使用，节点和订阅由各自客户端管理；配置不含订阅地址、账号或节点凭据。本文的“SSR”使用场景指 Shadowrocket 客户端，不表示此文件可导入任意 ShadowsocksR 软件。

- [下载完整配置](./shadowrocket-optimized.conf)
- [导入、日常使用、排错与回滚](./使用指南.md)
- [梅林配套方案](../merlin/README.md) · [梅林使用指南](../merlin/使用指南.md)

## 使用场景

| 场景 | 操作 | 分流与出口 |
| --- | --- | --- |
| 在家日常浏览 | 关闭 Shadowrocket，连接梅林 | 由路由器按大陆白名单分流，国内直连、海外使用香港主节点 |
| 在家使用 GPT 等服务 | 开启 Shadowrocket，选择能正常访问目标服务的节点 | 客户端规则接管；所有命中 `PROXY` 的服务使用当前节点 |
| 外出连接大陆手机热点或使用蜂窝网络 | 在需要代理的设备上开启 Shadowrocket | 客户端独立完成分流，无需家庭路由器或固定家庭 DNS |

Shadowrocket 首页“全局路由”必须设为“配置”，并选中本文件使用。选成“代理”会覆盖文件内的直连分流。

开启 Shadowrocket 后，不是只有 GPT 改变出口、其他海外网页仍自动走家庭香港节点。Viu 等地区内容也会随客户端所选节点变化。Mac 与 iPhone 使用同一规则文件，但节点选择和连接开关彼此独立；手机开启代理也不代表其热点下的其他设备自动使用该代理。

## 功能与规则顺序

规则按顺序匹配，先命中的策略生效。

| 层次 | 配置逻辑 | 作用 |
| --- | --- | --- |
| 局域网优先 | 本地名称直连；前置私网 IP 规则带 `no-resolve`；`[Host]` 将本地名称交给系统 DNS | 访问路由器、NAS 和局域网服务，避免为可按域名分流的请求提前解析 |
| 国内 App 与常用服务 | 微信、抖音、知乎、番茄、DeepSeek、Kimi，以及办公、NAS、国内视频/CDN、镜像等先于广告规则直连 | 减少国内服务误走代理及广告大类规则误伤核心请求的机会 |
| OpenAI 核心连接 | 登录、静态资源、文件、验证与实时连接相关域名先于广告规则代理 | 让这些请求使用同一客户端节点，并提供显式域名保底 |
| 广告与海外服务 | 保留广告拦截，以及 AI、流媒体、社交、购物、开发等分类规则 | 按服务区分 `REJECT`、`DIRECT` 和 `PROXY` |
| 游戏 | `SteamCN` 先直连，随后 `Game` 代理 | 优先处理下载/CDN 与连接管理请求，商店和社区按后续游戏规则处理 |
| Apple 与大类 | Apple IP 规则放在 AI 例外之后；Apple、Global、China 使用原生 `DOMAIN-SET` 与 `RULE-SET` 组合 | 域名集合与关键词、IP、User-Agent 等规则互补 |
| 最后兜底 | 允许解析的私网 IP 规则 → `GEOIP,CN,DIRECT` → `FINAL,PROXY` | 处理自定义私网别名与未被前面规则覆盖的请求 |

金融类 App 不新增专属规则，按使用习惯在启动前关闭 Shadowrocket。关闭客户端不会同时关闭梅林代理；若需要完全不经过代理，应另行确认路由器或所用网络的状态。配置不使用书签栏 Work 文件夹中的专用域名，也不固定某台 NAS 或某个家庭路由器的私有地址。

## DNS、传输与隐私边界

| 参数 | 设置 | 含义与限制 |
| --- | --- | --- |
| `dns-server` | 腾讯、阿里两个 DoH | 主解析器；列表顺序不等于严格逐个串行尝试 |
| `fallback-dns-server` | 国内普通 DNS 与 `system` | 主解析失败或超时时回退；不固定家庭 DNS，便于外出使用 |
| `dns-direct-fallback-proxy` | `false` | 直连解析失败不改经代理重试；必要时应排查当地 DNS 可达性 |
| `hijack-dns` | Google / Cloudflare 常见明文 DNS 地址的 53 端口 | 不使用 `*:53` 全量劫持；不涵盖所有硬编码 DNS 或 DoH |
| `block-quic` | `all-proxy` | 仅限制代理 QUIC，让支持回退的客户端改用 TCP；国内 QUIC 保持可用 |
| `ipv6` / `prefer-ipv6` | `true` / `false` | 允许 IPv6，不优先选择 IPv6；不改变家庭路由器的 IPv6 代理设置 |

`block-quic` 是代理传输兼容性设置，不保证回退协议一定是 HTTP/2，也不保证修复所有 SSE、WebSocket、实时语音或 App 连接问题。代理目标默认由代理端解析；局域网名称通过 `[Host]` 中的系统 DNS 映射单独处理。

配置不启用 MITM 或 HTTPS 解密。Google 中国入口的 URL Rewrite 保留，但不能据此保证 HTTPS 请求一定被重写。`localhost.weixin.qq.com` 的回环映射保留，不将其改成家庭设备地址。

## 规则来源与更新

公开配置的 `[Rule]` 有 150 个条目：107 个内联规则和 43 个远程引用。远程引用包括：

- [blackmatrix7/ios_rule_script 的 Shadowrocket 原生规则](https://github.com/blackmatrix7/ios_rule_script/tree/master/rule/Shadowrocket)，通过 jsDelivr 分发。
- [iab0x00/ProxyRules 的 AI.txt](https://github.com/iab0x00/ProxyRules/blob/main/Rule/AI.txt)，补充 AI 服务域名；国内 AI 的显式直连规则先匹配。

上游更新不等于设备缓存已更新。导入或调整配置后，应在客户端刷新远程规则并确认加载情况，具体操作见[使用指南](./使用指南.md#6-更新配置与远程规则)。远程不可用时，内联规则、GeoIP 与最终策略仍可处理请求，但不能保证等价于完整分类覆盖。DeepSeek 等显式域名仍需在服务变化时维护，不应理解为“永久零维护”。

## 验证记录与适用边界

在仓库根目录可运行离线配置回归：

```sh
node --test shadowrocket/tests/config.test.mjs
```

测试检查规则顺序、DNS、远程引用集合和名单格式，不模拟客户端匹配或证明远程内容可达。

2026-09-23 的本地实例验证包括：

- Mac Shadowrocket 已导入并启用当时的本地文件，全局路由为“配置”，43/43 个远程规则集 URL 加载完成。
- 原生规则测试结果为 `chatgpt.com → PROXY`、`kimi.com → DIRECT`。
- Mac 访问 ChatGPT `robots.txt`、GitHub、百度收到 HTTP 200；显式使用 Shadowrocket 本地 HTTP 代理访问 ChatGPT `robots.txt` 也收到 200。
- 本地已核对排除 Work 后的书签首页主机，并做关键域名/IP 静态检查；这不代表网页内全部 CDN 和功能均已逐一测试。

本仓库公开版移除了本地实例中的一条私人 API 精确主机规则，其余分流逻辑一致。不能把本地实例的加载记录表述为这个脱敏版本已在设备上加载。iPhone 与外出热点尚未实测；HTTP 200 仅证明相应请求基础可达，不证明账号登录、长时间流式输出、语音或所有 App 功能均正常。

## 本地私有规则

如有自用 API，可在本地文件第 10 层的注释占位处添加精确主机规则：

```ini
DOMAIN,api.example.com,PROXY
```

对确定需要直连的私有服务，可在广告规则之前添加精确的 `DIRECT` 规则；局域网别名还应确认系统 DNS 能解析。优先使用 `DOMAIN` 限定主机，不要随意扩大为整个云平台的 `DOMAIN-SUFFIX`。

私人规则、节点入口绕过清单、订阅、账号、完整梅林备份和书签原文件均应只保存在本地。更新公开版前先备份本地改动；导入新版后再按需合并，不要上传私有版本。
