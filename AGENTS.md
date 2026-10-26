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
- `mini-app-spec/`：**企业级「AI Agent 驱动轻应用平台」技术规范**（脱敏方法论版，单文件）。含整套框架设计、
  前端约定、数据管理、生命周期控制、接口清单与「依照本规范设计轻应用的标准流程」。
  顶部有「读者路由」表：判断适用性读 §0–§1，要照做读 §7，AI 动手先读 §6 再读 §7。
- `skills/windows-fresh-setup/`：**Windows 新装优化**（唯一项目，入口 `README.md`）—— 可执行层与原理层合在一处，编号 = 实际配置顺序：
  `scripts/setup.ps1` 七阶段（check/dev/apps/drivers/tune/link/verify）+ 16 个可单跑工具 ·
  `docs/01-baseline.md` 起点判定 · `docs/02-decisions.md` 做/不做决策 ·
  `docs/03-system-tweaks.md` 43 个调优值（正确值 / 判据 / 怎么验）· `docs/04-dev-and-apps.md` 开发环境与 13 项软件 ·
  `docs/05-params.md` 参数速查 · `docs/reference/{pitfalls,audit-criteria}.md` 陷阱与判定标准 ·
  `games/` 按游戏可回退优化（当前 `cs2/`，`check-<game>-readiness.ps1` + `apply-<game>-optimizations.ps1` 支持 `-WhatIf` / `-Revert`）。
  **硬约定：文档里的值必须与代码一致；只写结果不写过程；每条结论要有判据。**
  新增游戏按 `games/README.md` 模板加子目录；该目录脚本**必须 ASCII-only**（同上）。
- `docs/`：与 Windows 调优无关的专题记录。`windows-nas-smb-stability.md`：内网 NAS 稳定性专项 ——
  「NAS 不稳」定位到「睡眠唤醒后没有重连」，含事件时间对齐法、事件触发计划任务、**驱动器映射按会话+提权级别隔离**、
  先算链路天花板再优化，以及 3 项实测无收益并已回滚的尝试。
  `skill-self-audit.md`：**方法论** —— 如何把 skill 的「文档承诺」变成「可验证事实」
  （5 类缺陷、性能优化的等价性证明、环境缺陷与代码缺陷的区分），与 `windows-fresh-setup` 配套。
- `internal-audit-reform/`：AI复用制作内部审计汇报、H5、海报和电脑邮件长图的完整项目包，包含可编辑PPT、逐页口播、结果导向的内容/视觉规范、海报源文件及配图库。使用前阅读其 `README.md` 和项目级 `AGENTS.md`；当前页面中的业务条件和时限只适用于对应示例项目。
- `assets/`：根 `README.md` 的横幅素材。`banner.svg` 与 `banner-dark.svg` 是同一版式的浅色 / 深色两套，
  由 README 中的 `<picture>` 按 `prefers-color-scheme` 自动切换；**改动需同步两份**。
  字体走系统字体栈（`PingFang SC, Hiragino Sans GB, Noto Sans SC, Microsoft YaHei`），不内嵌外部字体文件。

## 使用流程

照片、截图或PDF用于内容整理及H5/PPT/海报任务时，先执行 [材料审阅工作流](./internal-audit-reform/workflows/照片与PDF材料审阅.md)：首次完整审阅形成资料索引，后续优先读取相关页MD，只在具体疑点或来源变更时回查图像。文字、结构、配色分别核对，不以历史记忆替代本次有效材料。

1. 判断用户诉求是否命中某 Skill 的 `description`
2. 命中 → **先读 `skills/<name>/SKILL.md`**（完整方法论 + 判断清单），再按其流程执行
3. 需跑脚本 → 读 `README.md` 确认参数与依赖，优先 `--dry-run` 预演

## 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 把图片/截图里的文字或数字改成别的内容（金额、日期、编号、字段名）。核心是字形克隆法，保真度远高于字体重绘 | [skills/screenshot-text-edit/SKILL.md](./skills/screenshot-text-edit/SKILL.md) |
| `windows-fresh-setup` | 把一台新装好的 Windows 机器一条命令配成「AI 开发 + 游戏」机并完成系统优化（**与原理层文档同一个项目**）：引导检查 → 装开发工具链 → 装便携软件 → 驱动分诊 → 安全调优（先快照）→ 注册关联 → 验收，出故障能按基线回滚。入口 `scripts/setup.ps1`（七阶段，含 `-Profile minimal|dev|full` 预设）+ **`scripts/bootstrap.ps1` 无 git 自举**，另有 **16 个可单独用的工具脚本**（含 `check-script-hygiene.ps1` 双宿主脚本体检、`test-tune-core.ps1` 纯函数自测）。为什么这么改见 `docs/`（起点判定 / 决策表 / 43 个调优值的判据 / 参数速查 / 陷阱与判定标准），按游戏见 `games/`。含**运行上下文矩阵**与「显卡稳定性」小节。核心纪律三条：不碰按需启动的服务、动系统前先拍快照、改完必须重启再验证 | [skills/windows-fresh-setup/SKILL.md](./skills/windows-fresh-setup/SKILL.md) |

## 环境

- 部分脚本依赖 macOS Vision OCR，**仅 macOS 可用**
- 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- `skills/windows-fresh-setup/` 下的脚本**仅 Windows 可用**，依赖 PowerShell 7+；
  **但计划任务与登录脚本会用 Windows PowerShell 5.1 调它们** —— 因此该目录的脚本一律 **ASCII-only**
  （5.1 按 ANSI 解码无 BOM 文件，任何中文都会让解析失败且表现为"任务静默失败、退出码 0x1"）。
  **改完该目录任何 `.ps1` 就跑一次 `scripts/check-script-hygiene.ps1`**（双宿主解析，不执行，秒级）
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

**改文档标题后必须复查内部锚点。** Markdown 里的内部锚点是**手写**的
（`[文字]` 后面跟一个以 `#` 开头的片段），改标题、改编号或用词都会让它**静默失效**
（GitHub 不报错，只是点了不跳）。
实测踩过：文档引用了 `#5.5-Markdown-编辑器选型` 与 `#6.1-卸载必须…`，
而这两节**从未存在**，光看"文中提到了 §5.5"是查不出来的。
判据：锚点 = 标题小写 → 去掉标点与符号 → 空格转连字符
（`## 6. 已确认健康 · 不需要动` → `#6-已确认健康-不需要动`，中间是**一个**连字符）。
改名后把该文件所有锚点链接逐条比对一遍实际标题。

> 注意别在正文里写锚点链接的**完整字面形式**（带右括号的那种），
> 链接检查器会把它当成真链接并报"锚点未定义"。
