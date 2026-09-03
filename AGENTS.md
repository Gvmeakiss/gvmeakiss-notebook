# AGENTS.md

给 AI Agent 的入口说明。关于本仓库有什么、怎么用，读这一份就够。

## 仓库定位

个人技术笔记本，收录可复用的配置、工具与 AI Skill。**公开仓库，内容必须脱敏。**

## 目录约定

```
skills/<name>/
├── SKILL.md          # Skill 定义（标准 frontmatter，可被 Skill 工具直接加载）
├── README.md         # 人读的详细说明、参数速查、常见坑
└── scripts/          # 配套 CLI 脚本，支持 --help，自包含
```

其他顶层目录为配置/笔记类资源，用法见各自 README。

## 使用流程

1. 判断用户诉求是否命中某 Skill 的 `description`
2. 命中 → **先读 `skills/<name>/SKILL.md`**（完整方法论 + 判断清单），再按其流程执行
3. 需跑脚本 → 读 `README.md` 确认参数与依赖，优先 `--dry-run` 预演

## 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 把图片/截图里的文字或数字改成别的内容（金额、日期、编号、字段名）。核心是字形克隆法，保真度远高于字体重绘 | [skills/screenshot-text-edit/SKILL.md](./skills/screenshot-text-edit/SKILL.md) |

## 环境

- 部分脚本依赖 macOS Vision OCR，**仅 macOS 可用**
- 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`

## 内容红线

提交到本仓库前必须确认：

- 真实公司名 / 客户名 → 泛化或代码（「客户 M」）
- 订单号、单据编号、人名 → 占位符或虚构值
- **原始业务截图、底稿、含客户数据的文件一律不提交**，只提交方法与脚本

## 更新 Skill 时

补齐四件套，保持一致：`SKILL.md`（方法论）、`README.md`（参数速查）、`scripts/`（工具）、
根 `README.md` 与 `AGENTS.md` 的索引。
