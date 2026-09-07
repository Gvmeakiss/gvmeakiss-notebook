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
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | 截图文字/数字高保真修改（字形克隆法），含 4 个 CLI 脚本 |

---

## 🤖 给 AI 的说明 · For AI Agents

> 本节供 AI Agent（CodeBuddy / WorkBuddy / Claude Code 等）读取，用于快速定位并使用本仓库的能力。

### 仓库约定

- `skills/<name>/SKILL.md` —— 每个子目录是一个**可独立加载的 Skill**，遵循标准 frontmatter 格式
  （`name` / `description` / `agent_created`），可被 Skill 工具直接加载
- `skills/<name>/README.md` —— 人读的详细说明与参数速查
- `skills/<name>/scripts/` —— 配套可执行脚本，均支持 `--help`，自包含无外部配置依赖
- 其他顶层目录为**配置 / 笔记 / 演示应用类**资源，按其中的 README 使用

### 使用方式

1. 判断用户诉求是否命中某个 Skill 的 `description`
2. 命中则**先读该目录下的 `SKILL.md`**（含完整方法论与判断清单），再按其中流程执行
3. 需要跑脚本时，先读 `README.md` 确认参数与依赖

### 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 「把图片/截图里的 X 改成 Y」「改一下截图中的金额/日期/编号」「P 图改数字」「标题也要改」 | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) |

### 演示应用 · Demo app

- `audit-kanban/`：纯前端离线看板（双击 `audit-kanban/index.html` 即可运行），演示「同事填报 → 专人汇总 → 经理看板」的部门工作台账流转，含 Excel 导入导出与周快照。演示代码与数据已泛化脱敏，仅供展示交互与构建方法。

### 环境

- 部分脚本依赖 macOS Vision 框架做 OCR，**仅 macOS 可用**
- Python 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- 详细环境要求见各 Skill 的 README

### 内容红线（重要）

本仓库为**公开仓库**。涉及业务场景的内容，提交前必须脱敏：

- 真实公司名 / 客户名 → 泛化描述或代码（如「某保险公司」「客户 M」）
- 订单号、单据编号、人名 → 占位符或虚构值
- **原始业务截图、底稿、含客户数据的文件一律不得提交**，只提交方法与脚本

---

<a name="en"></a>

# 🇬🇧 English

**Gvmeakiss Notebook — personal technical notebook with reusable configurations, tooling notes and AI skills.**

## 📌 Contents

| Path | Type | Description |
|---|---|---|
| [audit-kanban](./audit-kanban) | Demo app | Offline “audit work-progress kanban” demo (pure front-end, run by double-clicking index.html; desensitized & generic, with fabricated demo data and build/usage docs) |
| [shadowrocket](./shadowrocket) | Config | Shadowrocket general-purpose routing rules (CN/global split, ad-block, long-connection tuning) |
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | High-fidelity text/digit editing inside screenshots (glyph-cloning method), incl. 4 CLI scripts |

---

## 🤖 Notes for AI Agents

> For AI agents (CodeBuddy / WorkBuddy / Claude Code, etc.) to quickly locate and use the capabilities in this repo.

### Repo conventions

- `skills/<name>/SKILL.md` — each subdirectory is a **standalone loadable Skill** with standard frontmatter (`name` / `description` / `agent_created`); load it directly through the Skill tool
- `skills/<name>/README.md` — human-readable details & parameter quick reference
- `skills/<name>/scripts/` — bundled executable scripts, all supporting `--help`, self-contained
- Other top-level directories are config / notes / demo-app resources — follow their READMEs

### How to use

1. Match the user request against a Skill's `description`.
2. If matched, **read that directory's `SKILL.md` first** (full methodology & checklist), then follow its workflow.
3. Before running scripts, read `README.md` for parameters and dependencies.

### Available Skills

| Skill | Trigger | Entry |
|---|---|---|
| `screenshot-text-edit` | “Change X to Y in this screenshot”, edit amounts / dates / IDs / field names in an image | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) |

### Demo app

- `audit-kanban/`: a pure front-end offline kanban (open `audit-kanban/index.html` to run) demonstrating a department work-log flow of "member updates → consolidator merges → manager board", with Excel import/export and weekly snapshots. Demo code and data are generic/desensitized — for interaction and build reference only.

### Environment

- Some scripts rely on the macOS Vision framework for OCR — **macOS only**
- Python deps: `pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- See each Skill's README for detailed environment requirements.

### Content red lines (important)

This is a **public** repo. Any business-related content must be desensitized before committing:

- Real company / client names → generic descriptions or codes (e.g. “某保险公司”, “Client M”)
- Order numbers, document IDs, personal names → placeholders or fabricated values
- **Never commit raw business screenshots, workpapers, or files containing client data** — commit the method and scripts only.

---

> 本仓库仅收录与技术交流相关的通用配置与逻辑，不含任何客户数据、财务数据或工作底稿。
> *This repo only hosts generic, tech-related configurations and logic — no client data, financial data, or workpapers.*
