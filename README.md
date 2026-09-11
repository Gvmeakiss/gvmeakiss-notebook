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
| [shadowrocket](./shadowrocket) | 配置 · Config | Shadowrocket 通用分流配置（国内外分流 / 去广告 / 长连接优化） |
| [mini-app-spec](./mini-app-spec) | 技术规范 · Spec | 企业级「AI Agent 驱动轻应用平台」技术规范（脱敏方法论版）：静态导出 + BFF 中介 + SQL 预定义 + 原子替换部署，含 Agent 开发约定 |
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | 截图文字/数字高保真修改（字形克隆法），含 4 个 CLI 脚本 |

---

## 📦 模块介绍

### `audit-kanban/` · 稽核工作进度看板（演示应用）

纯前端离线看板，双击 `audit-kanban/index.html` 即可运行、无需部署。演示「同事填报 → 专人汇总 → 经理看板」的部门工作台账流转，含 Excel 导入导出与周快照。演示代码与数据已泛化脱敏，仅供展示交互与构建方法。

### `shadowrocket/` · 分流配置

Shadowrocket 通用分流规则：国内外分流、去广告、长连接优化，导入即用。

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
| [shadowrocket](./shadowrocket) | Config | Shadowrocket general-purpose routing rules (CN/global split, ad-block, long-connection tuning) |
| [mini-app-spec](./mini-app-spec) | Tech spec | Enterprise “AI-Agent-driven light-app platform” technical spec (desensitized methodology edition): static export + BFF mediation + predefined SQL + atomic-swap deployment, with Agent dev conventions |
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | High-fidelity text/digit editing inside screenshots (glyph-cloning method), incl. 4 CLI scripts |

---

## 📦 Module Overview

### `audit-kanban/` · Audit Work-Progress Kanban (demo app)

A pure front-end offline kanban — open `audit-kanban/index.html` to run, no deployment needed. Demonstrates a department work-log flow of "member updates → consolidator merges → manager board", with Excel import/export and weekly snapshots. Code and data are generic/desensitized, for interaction & build reference only.

### `shadowrocket/` · Routing Config

General-purpose Shadowrocket routing rules: CN/global split, ad-block, long-connection tuning. Import and use.

### `mini-app-spec/` · Light-App Platform Spec

Enterprise "AI-Agent-driven light-app platform" technical spec (desensitized methodology edition). Covers the overall framework, front-end conventions, database scheme, lifecycle control (5-step publish scripts + 3-level concurrency), API inventory and Agent dev conventions, plus a standard workflow for building light apps per the spec — for similar-platform design and AI-assisted development.

### `skills/screenshot-text-edit/` · Screenshot Text Edit (AI Skill)

High-fidelity editing of text/digits inside screenshots (glyph-cloning, pixel-identical glyphs). Ships 4 self-contained CLI scripts (all support `--help`) for ERP screens, reports, documents, etc. Triggers like "change X to Y in this screenshot".

---

> 本仓库仅收录与技术交流相关的通用配置与逻辑，不含任何客户数据、财务数据或工作底稿。
> *This repo only hosts generic, tech-related configurations and logic — no client data, financial data, or workpapers.*
