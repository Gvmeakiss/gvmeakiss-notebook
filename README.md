# 📓 Gvmeakiss Notebook

个人技术笔记本 —— 收录可复用的通用配置、工具说明与 AI Skill。

*Personal technical notebook — reusable configurations, tooling notes and AI skills.*

## 目录 · Contents

| 目录 | 类型 | 说明 |
|---|---|---|
| [skills/screenshot-text-edit](./skills/screenshot-text-edit) | AI Skill | 截图文字/数字高保真修改（字形克隆法），含 4 个 CLI 脚本 |
| [shadowrocket](./shadowrocket) | 配置 | Shadowrocket 通用分流配置（国内外分流 / 去广告 / 长连接优化） |

---

## 给 AI 的说明 · For AI Agents

> 本节供 AI Agent（CodeBuddy / WorkBuddy / Claude Code 等）读取，用于快速定位并使用本仓库的能力。

### 仓库约定

- `skills/<name>/SKILL.md` —— 每个子目录是一个**可独立加载的 Skill**，遵循标准 frontmatter 格式
  （`name` / `description` / `agent_created`），可被 Skill 工具直接加载
- `skills/<name>/README.md` —— 人读的详细说明与参数速查
- `skills/<name>/scripts/` —— 配套可执行脚本，均支持 `--help`，自包含无外部配置依赖
- 其他顶层目录为**配置/笔记类**资源，按其中的 README 使用

### 使用方式

1. 判断用户诉求是否命中某个 Skill 的 `description`
2. 命中则**先读该目录下的 `SKILL.md`**（含完整方法论与判断清单），再按其中流程执行
3. 需要跑脚本时，先读 `README.md` 确认参数与依赖

### 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 「把图片/截图里的 X 改成 Y」「改一下截图中的金额/日期/编号」「P 图改数字」「标题也要改」 | [SKILL.md](./skills/screenshot-text-edit/SKILL.md) |

### 环境

- 部分脚本依赖 macOS Vision 框架做 OCR，**仅 macOS 可用**
- Python 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- 详细环境要求见各 Skill 的 README

### 内容红线（重要）

本仓库为**公开仓库**。涉及业务场景的内容，提交前必须脱敏：

- 真实公司名 / 客户名 → 泛化描述或代码（如「客户 M」）
- 订单号、单据编号、人名 → 占位符或虚构值
- **原始业务截图、底稿、含客户数据的文件一律不得提交**，只提交方法与脚本

---

> 本仓库仅收录与技术交流相关的通用配置与逻辑，不含任何客户数据、财务数据或工作底稿。
