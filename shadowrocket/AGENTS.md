# AGENTS.md · shadowrocket

给 AI 的执行说明。给人看的说明在 [`README.md`](./README.md) 与 [`使用指南.md`](./使用指南.md)。

改动前先读「红线」，否则容易把私有内容带进公开仓库。

## 执行协议

| 步 | 动作 | 命令 | 通过判据 |
| --- | --- | --- | --- |
| 1 | 改前跑一遍基线 | `node --test shadowrocket/tests/*.test.mjs` | 退出码 0；失败先修基线，不要在红的基础上改 |
| 2 | 改 `.conf` | 只动 `[Rule]` 对应层或 `[General]`/`[Host]`/`[URL Rewrite]` | 见「改哪里」 |
| 3 | 复跑测试 | 同上 | 9 个用例全过 |
| 4 | 查空白 | `git diff --check` | 干净 |
| 5 | 脱敏扫描 | 搜订阅链接 / 节点入口 IP / 账号 / 书签 | 0 命中 |
| 6 | 提交 | 只提交 `.conf` 与文档 | 不含 `private-output/` |

**硬规则**

1. **规则顺序即语义** —— 规则按顺序匹配，先命中者生效。新增规则必须放到正确层级，不能追加到文件末尾。
2. **广告类大类规则必须晚于国内核心 App 与国内 AI** —— 否则会误伤微信、地图、小程序。
3. **测试不是形式检查** —— 第 5、6、7 个用例断言的就是"顺序正确"，顺序错会红。
4. **不新增订阅、节点、凭据、书签** —— 公开版只放规则。
5. **同步改动要成对** —— 动了 `shadowrocket-optimized.conf` 里的梅林公开域名，必须同时跑
   `merlin/` 下的一致性与重叠测试。

## 改哪里

`shadowrocket-optimized.conf` 是分层结构，按需改对应层，不要跨层搬规则：

| 层 | 位置 | 放什么 |
| --- | --- | --- |
| `[General]` | 文件头 | DNS（国内 DoH + 备用）、QUIC 屏蔽只针对代理连接 |
| `[Host]` | 局域网层附近 | 本地名称交给系统 DNS |
| `[Rule]` 第 1 层 | 最前 | 局域网直连；私网 IP 带 `no-resolve` |
| `[Rule]` 第 2 层 | 广告规则之前 | 移动核心 App（微信/抖音/知乎/番茄等）与国内 AI（DeepSeek/Kimi） |
| `[Rule]` 第 3 层 | 广告规则之前 | 办公云文档、NAS、国内视频/CDN、镜像 |
| `[Rule]` 中部 | — | 海外服务、广告、地区内容 |
| `[Rule]` 尾部 | 最后两条 | `GEOIP,CN` 然后 `FINAL` —— **顺序固定，不可调换** |
| `[URL Rewrite]` | — | 只保留 Google 中国入口重定向，不加新的 |

## 验证判据（9 个用例分别守什么）

| 用例 | 守的东西 |
| --- | --- |
| Only unique routing, DNS, hosts and safe rewrite sections are present | 段不重复、只允许安全段 |
| DNS is portable between home Wi-Fi and mainland mobile networks | 家庭 Wi-Fi 与大陆蜂窝都能用（不能只依赖家庭 DNS） |
| All 43 remote references retain their native format, source and policy | 43 条远程引用的格式/来源/策略未被改写 |
| Rules use recognized local syntax and end in GEOIP then FINAL | 本地语法合法，尾部是 `GEOIP,CN` → `FINAL` |
| Domestic core apps and AI precede ads; OpenAI retains proxy priority | 国内核心与国内 AI 早于广告；OpenAI 仍走代理优先 |
| Steam download exceptions and AI exceptions precede broader rules | 例外规则早于宽泛规则 |
| LAN addresses avoid early DNS and retain a resolving fallback near FINAL | 局域网不触发额外 DNS，且在 FINAL 前仍有可解析兜底 |
| URL rewrites are restricted to Google China entry-point redirects | 重写只限 Google 中国入口 |
| Merlin public domain lists are valid, unique and non-overlapping | 与 `merlin/` 的公开域名清单不冲突 |

## 常见失败怎么定位

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 「end in GEOIP then FINAL」红 | 把规则追加到了文件末尾 | 移回对应层，保持 `GEOIP,CN` / `FINAL` 在最后 |
| 「precede ads」红 | 新规则插在广告大类之后 | 上移到第 2/3 层 |
| 「Merlin public domain lists」红 | 与 `merlin/` 清单重复或重叠 | 改 `merlin/` 与这里任一侧，两边只留一份 |
| 「43 remote references」红 | 改了远程引用的策略或格式 | 还原该行，只加不改 |
| 「LAN addresses avoid early DNS」红 | 私网规则少了 `no-resolve` | 补上 |

## 红线

- **不提交**：订阅地址、节点入口与真实 IP、账号密码、完整路由器备份、浏览器书签、私人 API 主机
- 私人规则留在本地文件；公开版更新后按需本地合并，**不要上传私有版本**
- 不做设备侧实证就不要写"已验证生效" —— 静态检查通过 ≠ 客户端已加载 ≠ 实际连通
