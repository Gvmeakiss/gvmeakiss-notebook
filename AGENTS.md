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
- `shadowrocket/`：Mac / iPhone 通用分流配置、使用指南与离线配置检查。
- `merlin/`：梅林 fancyss 分流名单、使用指南、美国节点入口绕过生成工具；账号与节点备份仅在本地使用。

## 使用流程

1. 判断用户诉求是否命中某 Skill 的 `description`
2. 命中 → **先读 `skills/<name>/SKILL.md`**（完整方法论 + 判断清单），再按其流程执行
3. 需跑脚本 → 读 `README.md` 确认参数与依赖，优先 `--dry-run` 预演

## 可用 Skill

| Skill | 触发场景 | 入口 |
|---|---|---|
| `screenshot-text-edit` | 把图片/截图里的文字或数字改成别的内容（金额、日期、编号、字段名）。核心是字形克隆法，保真度远高于字体重绘 | [skills/screenshot-text-edit/SKILL.md](./skills/screenshot-text-edit/SKILL.md) |
| `win-dev-environment` | 在 Windows（尤其非管理员账户）上审计/修复/验证开发环境：装编程语言、配国内镜像、排查「工具明明装了却找不到」。核心是区分「真缺失」与 Store 存根 / PATH 陈旧 / 区域编码造成的「假缺失」 | [skills/win-dev-environment/SKILL.md](./skills/win-dev-environment/SKILL.md) |
| `win-portable-apps` | 在 Windows 非管理员账户上安装与盘点便携软件：装 md / 图片 / 视频查看器、NAS 工具，排查「软件装哪了」「默认打开程序改不掉」。核心是便携版路线、便携软件不进系统应用列表、默认程序受 UserChoice 的 Deny ACL + Hash 保护 | [skills/win-portable-apps/SKILL.md](./skills/win-portable-apps/SKILL.md) |

## 环境

- 部分脚本依赖 macOS Vision OCR，**仅 macOS 可用**
- 依赖：`pyobjc-framework-Vision` `pyobjc-framework-Quartz` `pillow`
- `skills/win-dev-environment/` 与 `skills/win-portable-apps/` 下的脚本**仅 Windows 可用**，依赖 PowerShell 7+

## 内容红线

提交到本仓库前必须确认：

- 真实公司名 / 客户名 → 泛化或代码（「客户 M」）
- 订单号、单据编号、人名 → 占位符或虚构值
- **原始业务截图、底稿、含客户数据的文件一律不提交**，只提交方法与脚本
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
