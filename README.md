<div align="center">

<a name="top"></a>

<!-- 主题自适应横幅：浅色 / 深色自动切换 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/banner-dark.svg">
  <img src="./assets/banner.svg" alt="Gvmeakiss Notebook — 个人技术笔记本" width="100%">
</picture>

[**🇨🇳 中文**](#-中文) &nbsp;·&nbsp; [**🇬🇧 English**](#-english)

</div>

---

<a name="zh"></a>

## 🇨🇳 中文

这里收录可复用的技术配置、实践记录和 AI 工具。**五个项目各自独立成篇** —— 每个目录都有自己的 `README.md`，按其中步骤安装、运行或复用即可。

### ⭐ 近期项目

> **内部审计整改汇报复用包** —— 一次做完，下次能直接复用：可编辑终稿、逐页口播稿、内容与视觉规范、配图素材库，另附 AI 接手说明。

| 交付物 | 说明 |
|---|---|
| 🖥️ **[可编辑终稿 PPT](./internal-audit-reform/交付成果/内部审计整改革新_可编辑终稿.pptx)** | 15 页汇报正文，版式与配色已定稿，可直接改写内容复用 |
| 🎙️ **[逐页口播稿](./internal-audit-reform/交付成果/内部审计整改革新_15页PPT配套口播稿.md)** | 与 PPT 逐页对应，另出 `.docx` 便于打印与批注 |
| 🎨 **[复用规范](./internal-audit-reform/复用规范)** | 配色与视觉设计要求、内容整理与页面规划要求 |
| 🖼️ **[素材库](./internal-audit-reform/素材库)** | 背景图、页面元素、侧边元素，成体系的配图资产 |

<p align="right"><a href="./internal-audit-reform"><b>进入项目 →</b></a></p>

### 🧭 项目导航

#### 稽核与业务应用

| 项目 | 类型 | 简介 | 入口 |
|---|---|---|---|
| **audit-kanban** | 演示应用 | 离线稽核工作进度看板：同事填报 → 专人汇总 → 经理看板。纯前端，双击 `index.html` 即用 | [目录](./audit-kanban) · [说明](./audit-kanban/README.md) · [使用手册](./audit-kanban/使用说明.md) |
| **audit-workbench** | 工程项目 | 同主题的 Next.js / React / TypeScript 工程版：团队分区、阶段历史、挽损分批、归档恢复与 SQLite DDL | [目录](./audit-workbench) · [说明](./audit-workbench/README.md) |
| **mini-app-spec** | 技术规范 | 企业级「AI Agent 驱动轻应用平台」的方法论、接口与开发约定 | [目录](./mini-app-spec) |

#### 配置与工具

| 项目 | 类型 | 简介 | 入口 |
|---|---|---|---|
| **shadowrocket** | 分流配置 | Mac / iPhone 通用分流规则：国内外分流、去广告、长连接优化 | [目录](./shadowrocket) · [说明](./shadowrocket/README.md) |
| **merlin** | 配置与工具 | 梅林 fancyss 分流名单、节点入口绕过生成工具 | [目录](./merlin) · [说明](./merlin/README.md) · [使用指南](./merlin/使用指南.md) |
| **Windows 环境配置记录** | 实践记录 | Windows 10 非管理员环境从零配到可用的实测记录：14 项问题总表与复现命令 | [阅读](./docs/windows-environment-setup.md) |
| **系统调优核查记录** | 实践记录 | 系统优化项的逐条核查依据，与 `win-ai-gaming-setup` 的调优阶段配套 | [阅读](./docs/system-tweaks-audit.md) |

#### AI Skills

| Skill | 用途 | 入口 |
|---|---|---|
| **screenshot-text-edit** | 截图文字 / 数字高保真修改：字形克隆法，保真度远高于字体重绘 | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) · [参数速查](./skills/screenshot-text-edit/README.md) |
| **win-ai-gaming-setup** | 新装 Windows 一条命令配成「AI 开发 + 游戏」机：七阶段自动装软件、做系统优化，可回滚 | [SKILL.md](./skills/win-ai-gaming-setup/SKILL.md) · [参数速查](./skills/win-ai-gaming-setup/README.md) |

### 📖 使用说明

- 从对应项目目录的 `README.md` 开始，按其中步骤安装、运行或复用。
- 配置、脚本和规范均按各自项目说明使用；涉及账号、订阅或本地环境的内容以本机设置为准。
- 仓库中的演示应用使用虚构数据；项目适用范围和复用边界以项目文档为准。
- 需要让 AI 接手时，先读 **[AGENTS.md](./AGENTS.md)** —— 仓库有什么、怎么用，一份就够。

---

<a name="en"></a>

## 🇬🇧 English

This repository collects reusable technical configurations, practical notes and AI tools. **Five standalone projects**, each with its own `README.md` as the entry point.

### ⭐ Featured project

> **Internal Audit Reform Presentation Kit** — built once, reusable next time: a finalized editable deck, a page-matched spoken script, content and visual standards, an image library, and an AI handoff guide.

| Deliverable | What it is |
|---|---|
| 🖥️ **[Editable deck (PPTX)](./internal-audit-reform/交付成果/内部审计整改革新_可编辑终稿.pptx)** | 15 pages with the layout and palette already settled — rewrite the content and reuse |
| 🎙️ **[Spoken script](./internal-audit-reform/交付成果/内部审计整改革新_15页PPT配套口播稿.md)** | Page-matched to the deck; also shipped as `.docx` for printing and comments |
| 🎨 **[Reuse standards](./internal-audit-reform/复用规范)** | Colour and visual requirements, content structuring and page planning rules |
| 🖼️ **[Asset library](./internal-audit-reform/素材库)** | Backgrounds, page elements and side elements as a coherent asset set |

<p align="right"><a href="./internal-audit-reform"><b>Open project →</b></a></p>

### 🧭 Project directory

#### Audit and business apps

| Project | Type | Description | Entry points |
|---|---|---|---|
| **audit-kanban** | Demo app | Offline audit work-progress board: member updates → consolidator merge → manager board. Pure front-end — double-click `index.html` | [Folder](./audit-kanban) · [Readme](./audit-kanban/README.md) |
| **audit-workbench** | Engineering project | The Next.js / React / TypeScript build of the same theme: team partitions, stage history, salvage batches, archive restore, SQLite DDL | [Folder](./audit-workbench) · [Readme](./audit-workbench/README.md) |
| **mini-app-spec** | Technical spec | Methods, APIs and development conventions for an AI-agent-driven light-app platform | [Folder](./mini-app-spec) |

#### Configurations and tools

| Project | Type | Description | Entry points |
|---|---|---|---|
| **shadowrocket** | Routing config | Mac / iPhone rules: CN / global split, ad-block, long-connection tuning | [Folder](./shadowrocket) · [Readme](./shadowrocket/README.md) |
| **merlin** | Config and tools | Merlin fancyss routing lists and an endpoint bypass generator | [Folder](./merlin) · [Readme](./merlin/README.md) |
| **Windows setup notes** | Notes | Turning a locked-down Windows 10 machine into a working dev box: 14 issues and reproducible commands | [Read](./docs/windows-environment-setup.md) |
| **System tweaks audit** | Notes | Item-by-item evidence behind each system tweak, paired with the `win-ai-gaming-setup` tuning phase | [Read](./docs/system-tweaks-audit.md) |

#### AI skills

| Skill | Purpose | Entry points |
|---|---|---|
| **screenshot-text-edit** | High-fidelity text and digit edits inside screenshots via glyph cloning | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) · [Reference](./skills/screenshot-text-edit/README.md) |
| **win-ai-gaming-setup** | One command turns a fresh Windows box into an AI-development + gaming machine, with rollback | [SKILL.md](./skills/win-ai-gaming-setup/SKILL.md) · [Reference](./skills/win-ai-gaming-setup/README.md) |

### 📖 How to use

- Start with the `README.md` in the relevant project folder.
- Follow each project's instructions; account, subscription and local-environment details remain machine-specific.
- Demo apps use fabricated data. Refer to each project guide for its scope and reuse boundaries.
- Handing this to an AI agent? Read **[AGENTS.md](./AGENTS.md)** first.

---

<div align="center">

<a href="#top"><code>⬆ 回到顶部 · Back to top</code></a>

<br><br>

<sub>*个人技术记录与可复用工具 · Personal notes and reusable tools*</sub>

</div>
