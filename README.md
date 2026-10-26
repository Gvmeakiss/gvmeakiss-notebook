<div align="center">

<a name="top"></a>

<!-- 主题自适应横幅：浅色 / 深色自动切换。
     文字已全部转为矢量轮廓（<path>），不依赖任何字体 —— GitHub 在服务端渲染 SVG，
     系统字体栈里没有中文字体时会出豆腐块。改版式请改 assets 下的 SVG 并保持两份同步。 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/banner-dark.svg">
  <img src="./assets/banner.svg" alt="Gvmeakiss Notebook — 个人技术笔记本：可复用配置、工具与 AI Skill" width="100%">
</picture>

[**🇨🇳 中文**](#zh) &nbsp;·&nbsp; [**🇬🇧 English**](#en)

**可复用的配置 · 实测的踩坑记录 · 可直接加载的 AI Skill**<br>
<sub>每个目录独立成篇，都有自己的 <code>README.md</code> —— 按其中步骤安装、运行或复用即可</sub>

[⭐ 近期项目](#featured-zh) &nbsp;·&nbsp;
[🧭 项目导航](#nav-zh) &nbsp;·&nbsp;
[🤖 AI Skills](#skills-zh) &nbsp;·&nbsp;
[📚 参考文档](#docs-zh)

</div>

---

<a name="zh"></a>

## 🇨🇳 中文

这里收录可复用的技术配置、实践记录和 AI 工具。**各项目独立成篇** —— 每个目录都有自己的 `README.md`，按其中步骤安装、运行或复用即可。

### ⭐ 近期项目

<a name="featured-zh"></a>

<div align="center">

**内部审计整改汇报复用包**

*一次核对并做完，下次能复用：可编辑 PPT、逐页口播稿、H5/海报设计规范、电脑邮件长图、配图素材库，另附 AI 接手说明*

</div>

| 交付物 | 说明 |
|---|---|
| 🖥️ **[可编辑 PPT 视觉样例](./internal-audit-reform/交付成果/内部审计整改革新_可编辑终稿.pptx)** | 15页配色、版式与原生对象参考；现行业务内容以经理18页版为准 |
| 🎙️ **[当前18页口播稿](./internal-audit-reform/案例/20261019_内部审计整改流程优化/内部审计整改流程优化_18页口播稿.md)** | 2026-10-20定稿，对应经理18页扫描版；另出 [Word](./internal-audit-reform/案例/20261019_内部审计整改流程优化/内部审计整改流程优化_18页口播稿.docx) 和[语义核对标准](./internal-audit-reform/复用规范/07_口播语义核对与定稿入库.md) |
| 🎨 **[复用规范](./internal-audit-reform/复用规范)** | [项目导航与结果导向](./internal-audit-reform/复用规范/00_项目导航与结果导向.md) · [配色与视觉设计](./internal-audit-reform/复用规范/01_配色与视觉设计要求.md) · [H5/海报/邮件长图](./internal-audit-reform/复用规范/06_H5海报与邮件长图设计.md) |
| 🖼️ **[电脑邮件版海报](./internal-audit-reform/交付成果/宣导海报_电脑邮件版/)** | 两页长图、构建源文件和导出说明，保留流程完整性并适配电脑邮件阅读 |
| 🖼️ **[素材库](./internal-audit-reform/素材库)** | 背景图、页面元素、侧边元素，以及面向 H5、PPT、海报的[可复用矢量组件](./internal-audit-reform/素材库/可复用矢量组件/README.md) |
| 📘 **[项目说明](./internal-audit-reform/README.md)** · **[AI 接手说明](./internal-audit-reform/AGENTS.md)** | 项目定位、复用边界与交给 AI 继续做的入口 |

<p align="center"><a href="./internal-audit-reform"><b>进入项目 →</b></a></p>

### 🧭 项目导航

<a name="nav-zh"></a>

#### 稽核与业务应用

| 项目 | 类型 | 简介 | 入口 |
|---|---|---|---|
| **audit-kanban** | 演示应用 | 离线稽核工作进度看板：同事填报 → 专人汇总 → 经理看板。纯前端，双击 `index.html` 即用 | [目录](./audit-kanban) · [说明](./audit-kanban/README.md) · [使用手册](./audit-kanban/使用说明.md) |
| **audit-workbench** | 工程项目 | 同主题的 Next.js / React / TypeScript 工程版：团队分区、阶段历史、挽损分批、归档恢复与 SQLite DDL。需 `npm ci` 后构建 | [目录](./audit-workbench) · [说明](./audit-workbench/README.md) · [使用说明](./audit-workbench/docs/使用说明.md) |
| **mini-app-spec** | 技术规范 | 企业级「AI Agent 驱动轻应用平台」的方法论、接口与开发约定 | [目录](./mini-app-spec) · [说明](./mini-app-spec/README.md) |
| **internal-audit-reform** | AI 复用项目 | 内部审计整改汇报复用包：可编辑 PPT、逐页口播稿、复用规范与配图素材库 | [目录](./internal-audit-reform) · [说明](./internal-audit-reform/README.md) |

#### 配置与工具

| 项目 | 类型 | 简介 | 入口 |
|---|---|---|---|
| **shadowrocket** | 分流配置 | Mac / iPhone 通用分流规则：国内外分流、去广告、长连接优化 | [目录](./shadowrocket) · [说明](./shadowrocket/README.md) · [使用指南](./shadowrocket/使用指南.md) |
| **merlin** | 配置与工具 | 梅林 fancyss 分流名单、节点入口绕过生成工具 | [目录](./merlin) · [说明](./merlin/README.md) · [使用指南](./merlin/使用指南.md) |
| **Windows 新装优化** | 项目 + 工具 | **一个项目两层**：能跑的脚本（七阶段 16 个工具）+ 为什么这么改的判据（起点 / 决策 / 45 个调优值 / 13 项软件 / 参数 / 陷阱与判定标准），按游戏可回退优化（当前 CS2），对齐 **98 项验收** | [项目入口](./skills/windows-fresh-setup/README.md) · [游戏优化](./skills/windows-fresh-setup/games/README.md) |
| **内网 NAS 稳定性记录** | 实践记录 | 把「NAS 不稳」定位到「睡眠唤醒后没有重连」的完整链条：事件时间对齐法、事件触发计划任务、映射的会话/提权隔离、先算链路天花板 | [阅读](./docs/windows-nas-smb-stability.md) |
| **Skill 自审方法论** | 方法 | 如何把「文档承诺」变成「可验证事实」：5 类真实缺陷、性能优化的等价性证明、环境缺陷与代码缺陷的区分 | [阅读](./docs/skill-self-audit.md) |


#### AI Skills

<a name="skills-zh"></a>

| Skill | 用途 | 入口 |
|---|---|---|
| **screenshot-text-edit** | 截图文字 / 数字高保真修改：字形克隆法，保真度远高于字体重绘 | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) · [参数速查](./skills/screenshot-text-edit/README.md) |

### 📖 使用说明

- 从对应项目目录的 `README.md` 开始，按其中步骤安装、运行或复用。
- 配置、脚本和规范均按各自项目说明使用；涉及账号、订阅或本地环境的内容以本机设置为准。
- 仓库中的演示应用使用虚构数据；项目适用范围和复用边界以项目文档为准。
- 需要让 AI 接手时，先读 **[AGENTS.md](./AGENTS.md)** —— 仓库有什么、怎么用，一份就够。

### 📚 参考与文档

<a name="docs-zh"></a>

> 支撑性文档：背景依据、验收记录与演示数据说明。需要追溯"为什么这么做"时从这里查。

<details>
<summary><b>▸ audit-kanban 过程文档</b>（使用手册 / 构建 / 验收 / 审阅 / 演示数据）</summary>

<br>

| 文档 | 内容 |
|---|---|
| [使用说明](./audit-kanban/使用说明.md) | 「稽核工作台使用说明」——面向填表人与汇总人的操作步骤 |
| [构建说明](./audit-kanban/构建说明.md) | 目录结构、构建与打包方式、离线运行前提 |
| [验收记录](./audit-kanban/验收记录.md) | 逐项验收结果与验收口径 |
| [审阅与改进建议](./audit-kanban/审阅与改进建议.md) | 稽核工作看板的审阅意见与后续改进项 |
| [易用性与视觉优化记录](./audit-kanban/易用性与视觉优化记录.md) | 易用性与视觉迭代的历史记录 |
| [演示数据说明](./audit-kanban/演示数据/演示数据说明.md) | 虚构演示数据（某保险公司个人非车稽核）的口径与生成方式 |
| [演示数据生成脚本](./audit-kanban/演示数据/generate-demo.cjs) | 可复现地重新生成演示数据 |

</details>

<details>
<summary><b>▸ 网络配置说明</b>（shadowrocket / merlin 使用指南）</summary>

<br>

| 文档 | 内容 |
|---|---|
| [shadowrocket 使用指南](./shadowrocket/使用指南.md) | Mac / iPhone 导入、分流验证与排错 |
| [merlin 使用指南](./merlin/使用指南.md) | 梅林 fancyss 名单应用、节点入口绕过生成与使用 |
| [shadowrocket/README](./shadowrocket/README.md) · [merlin/README](./merlin/README.md) | 两个项目的完整说明与离线检查方式 |

公开版不包含本地私有例外；不要用公开名单整体覆盖个人现有名单。

</details>

<details>
<summary><b>▸ Windows 新装优化与专题文档</b></summary>

<br>

| 文档 | 内容 |
|---|---|
| [Windows 新装优化](./skills/windows-fresh-setup/README.md) | 可执行层与原理层同一个项目：七阶段脚本 + 起点基线 / 做不做决策 / 45 个调优值的判据 / 13 项软件 / 参数速查 / 43 条陷阱 / 18 项判定标准，98 项验收一一对应 |
| [内网 NAS 稳定性记录](./docs/windows-nas-smb-stability.md) | 「NAS 不稳」的真因是唤醒后没有重连：事件时间对齐法、事件触发计划任务、映射的会话/提权隔离、吞吐天花板换算、以及 3 项实测无收益已回滚的尝试 |
| [Skill 自审方法论](./docs/skill-self-audit.md) | 把文档承诺变成可验证事实：5 类缺陷（描述不符 / 预演不可信 / 退出码失真 / 判定矛盾 / 静默吞错）、性能等价性证明、环境 vs 代码缺陷 |
| [screenshot-text-edit 参数速查](./skills/screenshot-text-edit/README.md) | CLI 脚本参数与调用示例 |

关系说明：**`skills/windows-fresh-setup/` 是一个项目，里面 `scripts/` 是可执行的方法、`docs/` 是为什么这么做与踩过的坑、`games/` 是按游戏的落地；`docs/`（顶层）是与 Windows 调优无关的专题记录**。

</details>

<details>
<summary><b>▸ 仓库级约定</b></summary>

<br>

| 文档 | 内容 |
|---|---|
| [AGENTS.md](./AGENTS.md) | 交给 AI Agent 的入口说明：仓库有什么、目录约定、内容红线、检查命令 |
| [skills/ 目录约定](./AGENTS.md) | Skill 四件套：`SKILL.md`（方法论）+ `README.md`（参数速查）+ `scripts/`（工具）+ 索引 |

</details>

---

<a name="en"></a>

## 🇬🇧 English

This repository collects reusable technical configurations, practical notes and AI tools. **Each project is standalone**, with its own `README.md` as the entry point.

<div align="center">

**Reusable configs · Field-tested notes · Drop-in AI skills**<br>
<sub>Every folder stands alone with its own <code>README.md</code> — follow it to install, run or reuse</sub>

[⭐ Featured](#featured-en) &nbsp;·&nbsp;
[🧭 Projects](#nav-en) &nbsp;·&nbsp;
[🤖 AI Skills](#skills-en) &nbsp;·&nbsp;
[📚 Docs](#docs-en)

</div>

### ⭐ Featured project

<a name="featured-en"></a>

<div align="center">

**Internal Audit Reform Presentation Kit**

*Verify it once, reuse the logic next time: an editable deck, page-matched script, H5/poster standards, desktop email poster, image library, and AI handoff guide*

</div>

| Deliverable | What it is |
|---|---|
| 🖥️ **[Editable visual sample (PPTX)](./internal-audit-reform/交付成果/内部审计整改革新_可编辑终稿.pptx)** | 15-page layout, palette and editable-object reference; current content follows the manager's 18-page version |
| 🎙️ **[Current 18-page script](./internal-audit-reform/案例/20261019_内部审计整改流程优化/内部审计整改流程优化_18页口播稿.md)** | Finalized on 2026-10-20 and matched to the 18-page scans; [Word](./internal-audit-reform/案例/20261019_内部审计整改流程优化/内部审计整改流程优化_18页口播稿.docx) and [semantic review standard](./internal-audit-reform/复用规范/07_口播语义核对与定稿入库.md) included |
| 🎨 **[Reuse standards](./internal-audit-reform/复用规范)** | [Result-first navigation](./internal-audit-reform/复用规范/00_项目导航与结果导向.md) · [Colour & visual requirements](./internal-audit-reform/复用规范/01_配色与视觉设计要求.md) · [H5/poster/email](./internal-audit-reform/复用规范/06_H5海报与邮件长图设计.md) |
| 🖼️ **[Desktop email poster](./internal-audit-reform/交付成果/宣导海报_电脑邮件版/)** | Two-panel long image, source HTML/CSS and export instructions |
| 🖼️ **[Asset library](./internal-audit-reform/素材库)** | Backgrounds, page elements and side elements as a coherent asset set |
| 📘 **[Project readme](./internal-audit-reform/README.md)** · **[AI handoff](./internal-audit-reform/AGENTS.md)** | Scope, reuse boundaries and the entry point for handing this to an agent |

<p align="center"><a href="./internal-audit-reform"><b>Open project →</b></a></p>

### 🧭 Project directory

<a name="nav-en"></a>

#### Audit and business apps

| Project | Type | Description | Entry points |
|---|---|---|---|
| **audit-kanban** | Demo app | Offline audit work-progress board: member updates → consolidator merge → manager board. Pure front-end — double-click `index.html` | [Folder](./audit-kanban) · [Readme](./audit-kanban/README.md) · [Manual](./audit-kanban/使用说明.md) |
| **audit-workbench** | Engineering project | The Next.js / React / TypeScript build: team partitions, stage history, salvage batches, archive restore, SQLite DDL. Needs `npm ci` | [Folder](./audit-workbench) · [Readme](./audit-workbench/README.md) · [Manual](./audit-workbench/docs/使用说明.md) |
| **mini-app-spec** | Technical spec | Methods, APIs and development conventions for an AI-agent-driven light-app platform | [Folder](./mini-app-spec) · [Readme](./mini-app-spec/README.md) |
| **internal-audit-reform** | AI-assisted project | Internal audit reform presentation kit: editable deck, page-matched script, reuse standards, image library | [Folder](./internal-audit-reform) · [Readme](./internal-audit-reform/README.md) |

#### Configurations and tools

| Project | Type | Description | Entry points |
|---|---|---|---|
| **shadowrocket** | Routing config | Mac / iPhone rules: CN / global split, ad-block, long-connection tuning | [Folder](./shadowrocket) · [Readme](./shadowrocket/README.md) · [Guide](./shadowrocket/使用指南.md) |
| **merlin** | Config and tools | Merlin fancyss routing lists and an endpoint bypass generator | [Folder](./merlin) · [Readme](./merlin/README.md) · [Guide](./merlin/使用指南.md) |
| **Windows fresh-install optimisation** | Project + tooling | **One project, two layers**: runnable scripts (7 phases, 17 tools) plus the reasoning behind every change (baseline, decisions, 45 tweaks with criteria, 13 apps, parameters, pitfalls and audit criteria), with revertable per-game tuning (CS2 for now) mapped to **98 acceptance checks** | [Entry](./skills/windows-fresh-setup/README.md) · [Games](./skills/windows-fresh-setup/games/README.md) |
| **NAS stability notes** | Notes | Tracing "the NAS feels unstable" to "nothing remounts it after sleep": event-time correlation, an event-triggered remount task, session/elevation isolation of drive mappings, and calculating the link ceiling before optimizing | [Read](./docs/windows-nas-smb-stability.md) |
| **Skill self-audit method** | Method | Turning documented promises into verifiable facts: five defect classes, proving an optimization is coverage-equivalent, and telling an environment quirk apart from a code bug | [Read](./docs/skill-self-audit.md) |

#### AI skills

<a name="skills-en"></a>

| Skill | Purpose | Entry points |
|---|---|---|
| **screenshot-text-edit** | High-fidelity text and digit edits inside screenshots via glyph cloning | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) · [Reference](./skills/screenshot-text-edit/README.md) |

### 📖 How to use

- Start with the `README.md` in the relevant project folder.
- Follow each project's instructions; account, subscription and local-environment details remain machine-specific.
- Demo apps use fabricated data. Refer to each project guide for its scope and reuse boundaries.
- Handing this to an AI agent? Read **[AGENTS.md](./AGENTS.md)** first.

### 📚 Reference documents

<a name="docs-en"></a>

> Supporting material: rationale, acceptance records and demo-data notes. Start here when tracing *why* something was done.

<details>
<summary><b>▸ audit-kanban process docs</b> (manual / build / acceptance / review / demo data)</summary>

<br>

| Document | Content |
|---|---|
| [Usage manual](./audit-kanban/使用说明.md) | Step-by-step operation for both submitters and the consolidator |
| [Build notes](./audit-kanban/构建说明.md) | Directory layout, build and packaging, offline prerequisites |
| [Acceptance record](./audit-kanban/验收记录.md) | Item-by-item acceptance results and criteria |
| [Review & improvement notes](./audit-kanban/审阅与改进建议.md) | Review findings and follow-up improvements |
| [Usability & visual log](./audit-kanban/易用性与视觉优化记录.md) | History of usability and visual iterations |
| [Demo data notes](./audit-kanban/演示数据/演示数据说明.md) | Scope and generation of the fabricated demo data |
| [Demo data generator](./audit-kanban/演示数据/generate-demo.cjs) | Reproducibly regenerate the demo data |

</details>

<details>
<summary><b>▸ Network configuration guides</b> (shadowrocket / merlin)</summary>

<br>

| Document | Content |
|---|---|
| [shadowrocket guide](./shadowrocket/使用指南.md) | Import, routing verification and troubleshooting on Mac / iPhone |
| [merlin guide](./merlin/使用指南.md) | Applying fancyss lists and generating endpoint bypasses |

The public edition excludes local private exceptions; never overwrite your personal lists wholesale with the public ones.

</details>

<details>
<summary><b>▸ Windows fresh-install optimisation and topic notes</b></summary>

<br>

| Document | Content |
|---|---|
| [Windows fresh-install optimisation](./skills/windows-fresh-setup/README.md) | Executable and explanatory layers in one project: 7-phase scripts plus baseline, do/don't decisions, 45 tweaks with criteria, 13 apps, parameters, 43 pitfalls and 18 audit criteria tied to 98 acceptance checks |
| [NAS stability notes](./docs/windows-nas-smb-stability.md) | "Unstable NAS" traced to a missing remount trigger after sleep: event-time correlation, an event-triggered scheduled task, mapping isolation by session/elevation, link-ceiling math, and three attempts that measured no benefit and were rolled back |
| [Skill self-audit method](./docs/skill-self-audit.md) | Verifying a skill's own claims: five defect classes, coverage-equivalence proof for performance work, and separating machine policy from code defects |

**The skill is the executable method; the docs explain why and what went wrong.**

</details>

<details>
<summary><b>▸ Repository conventions</b></summary>

<br>

| Document | Content |
|---|---|
| [AGENTS.md](./AGENTS.md) | Agent entry point: what's here, directory conventions, content red lines, check commands |

</details>

---

<div align="center">

<a href="#top"><code>⬆ 回到顶部 · Back to top</code></a>

<br><br>

<sub>*个人技术记录与可复用工具 · Personal notes and reusable tools*</sub>

</div>
