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

其他顶层目录为配置/笔记/演示应用类资源，用法见各自 README：

- `audit-kanban/`：纯前端离线「稽核工作进度看板」演示应用（脱敏），双击 `index.html` 即可运行；
  用途为演示「同事填报 → 专人汇总 → 经理看板」的部门工作台账，不含任何真实业务数据。
- `audit-workbench/`：同主题的 Next.js / React / TypeScript 工程版（脱敏），需 `npm ci` 后构建，
  不是双击 HTML 的离线版；含团队分区、长期阶段历史、挽损分批明细、归档恢复与 SQLite DDL。
  运行 `npm test`（Node 内置测试运行器 + Python 3）、`npm run typecheck`、`npm run build` 验证。
  它是 `audit-kanban` 的工程版实现，**共用同一入口说明**，在根 `README.md` 中并入「稽核与业务应用」而非单列项目。
- `shadowrocket/`：Mac / iPhone 通用分流配置、使用指南与离线配置检查。
- `merlin/`：梅林 fancyss 分流名单、使用指南、美国节点入口绕过生成工具；账号与节点备份仅在本地使用。
- `docs/`：过程与踩坑记录。`windows-environment-setup.md` 是在一台 Windows 10 非管理员机器上
  把开发环境与常用软件从零配置到可用的实测记录（14 项问题总表 + Windows 专属陷阱）；
  `windows-environment-setup-win11.md` 是**互补的另一半** —— 一台"已经优化过"的 Windows 11 管理员机的
  逐项复核（真损害 / 被累积更新删掉的调优值 / **审计者自己的 3 处误判**，含「判定标准对错对照」表）。
  与 `win-ai-gaming-setup` 配套：**Skill 是可执行的方法，docs 是为什么这么做、以及踩过的坑**。
- `internal-audit-reform/`：AI复用制作内部审计整改汇报的完整项目包，包含可编辑PPT、逐页口播、复用规范及配图库。使用前阅读其 `README.md` 和项目级 `AGENTS.md`；当前页面中的业务条件和时限只适用于对应示例项目。
- `assets/`：根 `README.md` 的横幅素材。`banner.svg` 与 `banner-dark.svg` 是同一版式的浅色 / 深色两套，
  由 README 中的 `<picture>` 按 `prefers-color-scheme` 自动切换；**改动需同步两份**。
  字体走系统字体栈（`PingFang SC, Hiragino Sans GB, Noto Sans SC, Microsoft YaHei`），不内嵌外部字体文件。

## 使用流程

1. 判断用户诉求是否命中某 Skill 的 `description`
2. 命中 → **先读 `skills/<name>/SKILL.md`**（完整方法论 + 判断清单），再按其流程执行
3. 需跑脚本 → 读 `README.md` 确认参数与依赖，优先 `--dry-run` 预演

## 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 把图片/截图里的文字或数字改成别的内容（金额、日期、编号、字段名）。核心是字形克隆法，保真度远高于字体重绘 | [skills/screenshot-text-edit/SKILL.md](./skills/screenshot-text-edit/SKILL.md) |
| `win-ai-gaming-setup` | 把一台新装好的 Windows 机器一条命令配成「AI 开发 + 游戏」机并完成系统优化：引导检查 → 装开发工具链 → 装便携软件 → 驱动分诊 → 安全调优（先快照）→ 注册关联 → 验收，出故障能按基线回滚。唯一入口 `scripts/setup.ps1`（七阶段）。另含「显卡稳定性」小节（崩溃/黑屏/TDR 的取证与处置）。核心纪律三条：不碰按需启动的服务、动系统前先拍快照、改完必须重启再验证 | [skills/win-ai-gaming-setup/SKILL.md](./skills/win-ai-gaming-setup/SKILL.md) |

## 环境

- 部分脚本依赖 macOS Vision OCR，**仅 macOS 可用**
- 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- `skills/win-ai-gaming-setup/` 下的脚本**仅 Windows 可用**，依赖 PowerShell 7+
- 其中 `-Restore` / `-Repair` / `-Reset` 与 `-Phase tune` 需管理员权限；
  快照目录含自启项导出（可能含本机路径），**属私有数据，不要提交**

## 内容红线

提交到本仓库前必须确认：

- 真实公司名 / 客户名 → 泛化或代码（「客户 M」）
- 订单号、单据编号、人名 → 占位符或虚构值
- **原始业务截图、底稿、含客户数据的文件一律不提交**，只提交方法与脚本
- `internal-audit-reform/` 是项目所有者明确要求纳入此公开仓库的专门目录。该目录现有交付材料不构成新增源材料的公开授权；其他内部来源文件仍按上述规则处理，新增内容需对照当次明确范围审核
- 网络配置不得提交订阅链接、节点凭据、私人 API 主机、真实节点入口/IP 清单、浏览器书签和完整路由器备份；生成结果放入已忽略的 `private-output/`。

## 网络配置检查

修改 `shadowrocket/` 或 `merlin/` 后运行：

```sh
node --test shadowrocket/tests/*.test.mjs merlin/tests/*.test.mjs
git diff --check
```

静态检查不等于设备已加载；客户端导入、路由器应用与实际连通结果应分别说明。公开版不包含本地私有例外，不要用公开名单整体覆盖个人现有名单。

## 更新 Skill 时

补齐四件套，保持一致：`SKILL.md`（方法论）、`README.md`（参数速查）、`scripts/`（工具）、
根 `README.md` 与 `AGENTS.md` 的索引。
