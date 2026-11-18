# Passwall 分流优化（iStoreOS / OpenWrt）

更新日期：2026-11-18。

把 [Shadowrocket 配置](../shadowrocket/README.md) 的分层思路和 [梅林 fancyss](../merlin/README.md) 的路由器侧参数，落到 **Passwall（luci-app-passwall）** 的字段上。本目录只记录方法与通用域名，**不含订阅、节点、凭据、路由器备份**。

- [使用指南](./使用指南.md)：备份、合并名单、改参数、验收、排错、回滚
- [执行协议](./AGENTS.md)：给 AI 的改动边界与判据

## 适用场景

| 场景 | 路由器 | 客户端 |
| --- | --- | --- |
| 在家日常浏览 | 开启 Passwall：国内直连、海外走香港主节点 | 关闭客户端代理 |
| 在家使用 GPT / Claude | 同上，GPT 由路由器默认出口（香港）承载 | 需要其他地区出口时，再开客户端并选节点 |
| 外出热点 / 蜂窝 | 不参与 | 由客户端自己的配置分流 |

路由器只认一个主节点时，所有海外服务共用这个出口；不想共用就切换节点，或在 Passwall 的「分流」里给规则组单独绑定节点。

## 分流与规则顺序

Passwall 26.x（nftables 模式）按下面的顺序匹配，先命中先返回：

| 顺序 | 集合 | 结果 |
| --- | --- | --- |
| 1 | 阻断名单 `block_host` | 拒绝 |
| 2 | 直连名单 `direct_host` | 直连 |
| 3 | 代理名单 `proxy_host` | 走代理 |
| 4 | GFW 名单 `gfwlist` | 走代理 |
| 5 | 国内域名 / 网段 `chnlist` `chnroute` | 大陆白名单下直连 |
| 6 | 默认 | 由 `tcp_proxy_mode` / `udp_proxy_mode` 决定 |

由此得到两条硬约束：

1. **直连集合优先于代理集合**。同一个域名或互为父子域时，以直连为准；公开名单必须保证两边不重叠，否则代理规则是死规则。
2. **广告/阻断规则必须最靠前**，所以它最先命中。这也是不轻易启用大而全广告名单的原因：会盖住国内核心 App。

DNS 侧由 `chinadns-ng` 分组查询：

| 分组 | 上游 | 说明 |
| --- | --- | --- |
| 代理名单 | 可信 DNS，经代理链路 | 避免污染 |
| 直连名单 | 国内 DNS | 拿到就近 CDN |
| GFW / 国内 | 可信 / 国内 | 按名单分流 |
| 未命中 | 两边同查 | `default-tag=none`：国内结果优先，国内空应答不采信 |

## 参数基线

以下字段名对应 `luci-app-passwall` 26.x 的 UCI 结构，其他版本先核对字段再改。

| 设置 | 本次值 | 作用与边界 |
| --- | --- | --- |
| 主开关 | `enabled=1` | — |
| 主节点 | 香港节点 | 实测延迟最低的一组；不按网页语言自动换地区 |
| 中国名单 | `chn_list=direct` | 大陆白名单：国内直连，其余按规则 |
| TCP / UDP 默认代理 | `proxy` / `proxy` | 未命中名单时走代理 |
| DNS 分流 | `dns_shunt=chinadns-ng` | 域名与解析结果双重判断 |
| 国内 DNS | `direct_dns=223.5.5.5`，`direct_dns_mode=udp` | 不依赖上游路由器 DNS |
| 可信 DNS | `remote_dns=1.1.1.1`，`dns_mode=tcp` | TCP 查询，经代理，不裸奔 |
| 默认标签 | `chinadns_ng_default_tag=none` | 智能判断，拒绝国内空应答 |
| DNS 劫持 | `dns_redirect=1` | 接管局域网明文 DNS；不接管应用内 DoH/DoT |
| 代理域名 AAAA | `filter_proxy_ipv6=1` | 代理域名不下发 IPv6，直连保留 |
| UDP 代理 | `udp_proxy_mode=proxy` | 保留游戏 / 语音能力 |
| 海外 QUIC | `udp_proxy_drop_ports=443` | 只作用于走代理的流量，国内 QUIC 不受影响 |
| IPv6 代理 | `ipv6_tproxy=0` | 与参考方案一致；见「边界」 |
| TCP 代理端口 | 默认常用端口 | **不要照抄 all**，见下节 |
| 透明代理 | `tcp_proxy_way=redirect`，`prefer_nft=1` | nftables 重定向 |
| 本机 / 局域网代理 | `localhost_proxy=1`，`client_proxy=1` | 路由器自身与局域网都按规则分流 |

## 版本差异（26.8 → 26.11）

升级到 26.11.11 时实测到的三处变化，升级前先确认版本：

| 项目 | 26.8.x 及更早 | 26.11.x |
| --- | --- | --- |
| 用户名单目录 | `/usr/share/passwall/rules` | `/etc/passwall/rules`（升级会覆盖 `/usr/share` 下的同名文件） |
| 主节点字段 | `tcp_node` / `udp_node` | `node` / `node_socks_port` |
| 规则缓存 | 无 | `/tmp/etc/passwall_tmp/user_rules`，带 `_ok` 标记；改名单后需删缓存或重启才会重建 |
| 自动更新 cron | `lua … rule_update.lua log all cron` | `setsid lua … rule_update.lua log all cron` |

26.11 的用户名单以 `/etc/passwall/rules` 为准；`/usr/share/passwall/rules` 留作系统默认，升级时会被包覆盖。升级后如果发现分流名单“变短了”，先查这里。

## 名单怎么合并

公开名单拆成「一份底表 + 两份增量」，避免同一批域名在两个项目里各存一份：

| 文件 | 条数 | 用途 |
| --- | --- | --- |
| [`../merlin/direct-domains.txt`](../merlin/direct-domains.txt) | 119 | 通用直连域名（国内 App、办公、媒体、Steam 国内 CDN） |
| [`../merlin/proxy-domains.txt`](../merlin/proxy-domains.txt) | 49 | 通用代理域名（海外 AI、开发、社交、流媒体） |
| [`direct-additions.txt`](./direct-additions.txt) | 25 | Passwall 本地基线里、底表没有的直连条目（Apple 账户、系统更新、DoH/DoT、PayPal 等） |
| [`proxy-additions.txt`](./proxy-additions.txt) | 17 | 同上，代理侧（Google 地区域名、流媒体、社交、Xiaomi 服务等） |

合并结果：直连 **144** 条（119 + 25），代理 **66** 条（49 + 17）。两份增量与底表**不允许重叠**，同名或互为子域只留一边。

`apple-relay.apple.com` 不列入：它被直连 `apple.com` 覆盖，代理规则永远不会命中。需要 iCloud Private Relay 走代理时，应先把 `apple.com` 从直连侧移除，而不是叠加。

## 没有照抄的项

### TCP 端口：不要照抄 `all`

参考方案给 fancyss 的建议是「默认 TCP 端口 `all`」，让所有端口参与分流。在 Passwall 上直接照抄会踩坑：

- 实测所用订阅节点只放行 443 等常用端口；`8443`、`2053`、`2087`、`8080` 经节点连接全部超时，而同样的地址**直连反而可用**。
- 把 `tcp_redir_ports` 改成 `1:65535` 后，这些本来能直连的高端口站点会被送进代理黑洞。
- 结论：保持默认常用端口列表。确实需要代理某个非标准端口时，先单独验证节点是否放行（`tcping -p <端口>`），再决定是否加。

### 其他保持原状的项

| 项 | 选择 | 原因 |
| --- | --- | --- |
| UDP 代理 | 开启 | Passwall + Xray 的 UDP 转发可用；关闭会损失游戏 / 语音。fancyss 关闭是那套实现的限制 |
| 广告屏蔽 | 未启用 | 阻断集合优先级最高，大名单容易误伤微信、支付类 App；要开先小名单验证 |
| IPv6 代理 | 关闭 | 需要节点支持 IPv6 出口，未验证前不动 |
| 订阅自动更新 | 维持「开机更新」 | 周更会引入节点变动风险；需要时手动更新并复核主节点 |

## 实测记录

2026-11-18，iStoreOS 24.10.8 + `luci-app-passwall` 26.8.12（当天升级到 26.11.11 后复测），x86_64；主节点为香港线路；客户端为 Mac（走路由器透明代理）。以下为一次性验收结果，不代表所有网络与时段。

| 检查项 | 结果 |
| --- | --- |
| `google.com/generate_204` | 204，0.26–0.41 s |
| `github.com` | 200，0.7–1.6 s |
| `chatgpt.com/robots.txt` | 403，0.26 s（Cloudflare 对爬虫的常规拦截，链路可达） |
| `baidu.com` | 200，0.10–0.12 s |
| `zhihu.com` | 302，0.13–0.14 s |
| `kimi.com` / `deepseek.com` | 200，0.13–0.22 s |
| 国内 DNS 解析 | 12–16 ms |
| 集合命中 | 知乎解析 IP 在 `psw_white`，OpenAI 解析 IP 在 `psw_black` |
| 香港节点 TCP 延迟 | 10 个节点中 8 个响应，40–45 ms |
| 新加坡 / 美国节点 | 约 200 ms / 约 255 ms（仅作对比，未启用） |
| 规则库 | chnlist 1.44 MB、chnroute 189 KB、chnroute6 128 KB、gfwlist 390 KB |

静态检查通过 ≠ 设备已加载 ≠ 业务全部正常：ChatGPT 只验证到 robots.txt 可达，未验证登录、长对话与语音；iPhone 与其他固件未实测。

## 边界

- **客户端自带 DoH/DoT 时**，DNS 劫持不生效，分流按客户端解析结果走；这是参考方案也承认的边界。
- **路由器自身的 IPv6 出站不经过代理**（`ipv6_tproxy=0`）。局域网没有全局 IPv6 时影响有限；有 IPv6 时需单独验证是否泄漏。
- **规则更新不等于配置更新**：名单刷新只换 `chnlist`/`chnroute`/`gfwlist`，`direct_host`、`proxy_host` 需要自行合并维护。
- **不同 Passwall 版本字段可能改名**，改之前先对照本机 LuCI 或 `uci show passwall`。

## 文件

| 文件 | 用途 |
| --- | --- |
| [`README.md`](./README.md) | 方案、参数基线、实测与边界 |
| [`使用指南.md`](./使用指南.md) | 备份、合并、应用、验收、回滚 |
| [`AGENTS.md`](./AGENTS.md) | AI 改动协议与红线 |
| [`direct-additions.txt`](./direct-additions.txt) · [`proxy-additions.txt`](./proxy-additions.txt) | 底表之外的增量名单 |
| [`tests/passwall.test.mjs`](./tests/passwall.test.mjs) | 离线检查：名单格式、数量、重叠、脱敏、文档一致性 |

## 来源

- 参考思路：[shadowrocket](../shadowrocket/README.md) 的规则分层与 [`merlin`](../merlin/README.md) 的参数基线
- Passwall 规则顺序与 DNS 分组：本机 `/usr/share/passwall/nftables.sh`、`helper_chinadns_add.lua` 与运行中的 `chinadns_ng.conf`（26.8.12 / 26.11.11）
- 名单来源：[blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script)、[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)、[felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)
