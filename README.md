<p align="center">
  <b>Language · 语言</b>&nbsp;&nbsp;
  <a href="#zh"><code>🇨🇳 中文</code></a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="#en"><code>🇬🇧 English</code></a>
</p>

# 📓 Gvmeakiss Notebook

**个人技术笔记本 —— 收录可复用的通用配置、工具说明与 AI Skill。**
*Personal technical notebook — reusable configurations, tooling notes and AI skills.*

---

<a name="zh"></a>

# 🇨🇳 中文

## 📌 目录 · Contents

| 目录 | 类型 | 说明 |
|---|---|---|
| [audit-kanban](./audit-kanban) | 演示应用 · Demo | 离线「稽核工作进度看板」演示版（纯前端，双击即用；脱敏泛化，含虚构演示数据与构建/使用文档） |
| [shadowrocket](./shadowrocket) | 配置 · Config | Mac / iPhone 通用分流：国内 App、海外 AI、局域网、独立移动网络使用与排错指南 |
| [merlin](./merlin) | 配置与工具 · Config / Tools | 梅林 fancyss 香港日常出口、分流名单与全部美国节点入口绕过生成工具 |
| [mini-app-spec](./mini-app-spec) | 技术规范 · Spec | 企业级「AI Agent 驱动轻应用平台」技术规范（脱敏方法论版）：静态导出 + BFF 中介 + SQL 预定义 + 原子替换部署，含 Agent 开发约定 |
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | 截图文字/数字高保真修改（字形克隆法），含 4 个 CLI 脚本 |

---

## 📦 模块介绍

### `audit-kanban/` · 稽核工作进度看板（演示应用）

纯前端离线看板，双击 `audit-kanban/index.html` 即可运行、无需部署。演示「同事填报 → 专人汇总 → 经理看板」的部门工作台账流转，含 Excel 导入导出与周快照。演示代码与数据已泛化脱敏，仅供展示交互与构建方法。

### `shadowrocket/` · 分流配置

Mac / iPhone 共用的 Shadowrocket 分流配置：国内 App 与局域网直连，海外 AI、内容和开发服务使用当前代理节点，兼顾在家叠加梅林与外出大陆热点。节点和订阅由客户端自行管理。

[下载配置](./shadowrocket/shadowrocket-optimized.conf) · [使用指南](./shadowrocket/使用指南.md)

### `merlin/` · 梅林分流与节点绕过

面向 fancyss 3.5.30 的配置说明与公开名单：日常海外访问由香港节点处理，客户端额外开启时可让全部美国节点入口绕过路由器代理。提供从本地 fancyss 备份生成入口域名和 IPv4 `/32` 清单的工具，不发布真实订阅或节点地址。

[功能与参数](./merlin/README.md) · [使用指南](./merlin/使用指南.md)

2026-09-23 更新保留既有服务规则，补齐国内 AI、办公/NAS、OpenAI 核心连接和 DNS 回退配置。公开版不含私人域名与节点入口；个人已应用配置、书签核验明细及完整备份仅保存在本地。

### `mini-app-spec/` · 轻应用平台技术规范

企业级「AI Agent 驱动的轻应用平台」技术规范（脱敏方法论版）。覆盖整体框架、前端约定、数据库方案、生命周期控制（5 步发布脚本 + 三级并发）、接口清单与 Agent 开发约定，并附「依照规范设计轻应用」的标准流程，供同类平台设计与 AI 开发参考。

### `skills/screenshot-text-edit/` · 截图改字（AI Skill）

高保真修改截图中的文字与数字（字形克隆法，字形像素级一致）。含 4 个自包含 CLI 脚本（均支持 `--help`），适用于 ERP 截图、报表、单据等改数改字场景；触发词如「把截图里的 X 改成 Y」。

---

<a name="en"></a>

# 🇬🇧 English

**Gvmeakiss Notebook — personal technical notebook with reusable configurations, tooling notes and AI skills.**

## 📌 Contents

| Path | Type | Description |
|---|---|---|
| [audit-kanban](./audit-kanban) | Demo app | Offline “audit work-progress kanban” demo (pure front-end, run by double-clicking index.html; desensitized & generic, with fabricated demo data and build/usage docs) |
| [shadowrocket](./shadowrocket) | Config | Shared Mac / iPhone routing for domestic apps, overseas AI, LAN and mobile networks, with a usage guide |
| [merlin](./merlin) | Config / Tools | Merlin fancyss routing lists, daily Hong Kong egress and a local US-node endpoint bypass generator |
| [mini-app-spec](./mini-app-spec) | Tech spec | Enterprise “AI-Agent-driven light-app platform” technical spec (desensitized methodology edition): static export + BFF mediation + predefined SQL + atomic-swap deployment, with Agent dev conventions |
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | High-fidelity text/digit editing inside screenshots (glyph-cloning method), incl. 4 CLI scripts |

---

## 📦 Module Overview

### `audit-kanban/` · Audit Work-Progress Kanban (demo app)

A pure front-end offline kanban — open `audit-kanban/index.html` to run, no deployment needed. Demonstrates a department work-log flow of "member updates → consolidator merges → manager board", with Excel import/export and weekly snapshots. Code and data are generic/desensitized, for interaction & build reference only.

### `shadowrocket/` · Routing Config

Shared Mac / iPhone rules for domestic direct access, overseas services and LAN discovery, usable both with a home router and independently on mainland mobile networks. Keep subscriptions and credentials in the client.

[Config](./shadowrocket/shadowrocket-optimized.conf) · [Usage guide (Chinese)](./shadowrocket/使用指南.md)

### `merlin/` · Merlin Routing and Endpoint Bypass

Routing lists and a guide for fancyss 3.5.30: keep Hong Kong as the daily router egress and bypass the router proxy for client-side US-node endpoints. Generate exact endpoint lists locally from a private fancyss backup; never upload subscriptions, credentials or endpoint inventories.

[Overview](./merlin/README.md) · [Usage guide (Chinese)](./merlin/使用指南.md)

The 2026-09-23 update retains existing service coverage and adds domestic AI, office/NAS services, core OpenAI routing and portable DNS fallback. Private exceptions, bookmark reports and full device backups are intentionally excluded from this public repository.

### `mini-app-spec/` · Light-App Platform Spec

Enterprise "AI-Agent-driven light-app platform" technical spec (desensitized methodology edition). Covers the overall framework, front-end conventions, database scheme, lifecycle control (5-step publish scripts + 3-level concurrency), API inventory and Agent dev conventions, plus a standard workflow for building light apps per the spec — for similar-platform design and AI-assisted development.

### `skills/screenshot-text-edit/` · Screenshot Text Edit (AI Skill)

High-fidelity editing of text/digits inside screenshots (glyph-cloning, pixel-identical glyphs). Ships 4 self-contained CLI scripts (all support `--help`) for ERP screens, reports, documents, etc. Triggers like "change X to Y in this screenshot".

---

> 本仓库仅收录与技术交流相关的通用配置与逻辑，不含任何客户数据、财务数据或工作底稿。
> *This repo only hosts generic, tech-related configurations and logic — no client data, financial data, or workpapers.*
