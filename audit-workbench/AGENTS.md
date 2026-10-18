# AGENTS.md · audit-workbench

给 AI 的执行说明。给人看的说明在 [`README.md`](./README.md) 与 [`docs/使用说明.md`](./docs/使用说明.md)。

公开工程演示版：**不能加入真实台账、内部规范、应用编号、私有接口、凭据或业务截图。**

## 执行协议

| 步 | 动作 | 命令 | 通过判据 |
| --- | --- | --- | --- |
| 1 | 装依赖（首次） | `npm ci` | 退出码 0 |
| 2 | 改前基线 | `npm test` 与 `npm run typecheck` | 都通过；红的不要在上面继续改 |
| 3 | 改代码 | 见「改哪里」 | 只动对应边界内的层 |
| 4 | 类型检查 | `npm run typecheck` | 无错误 |
| 5 | 单测 | `npm test` | 全部通过 |
| 6 | 构建 | `npm run build` | 成功，产物在 `next-app/out/` |
| 7 | 浏览器回归（涉及 UI 时） | `tests/browser-dashboard.mjs`、`tests/browser-quick-notes.mjs` | 需要 Playwright + Chrome；`PLAYWRIGHT_MODULE` / `AUDIT_TEST_URL` / `AUDIT_BROWSER_CHANNEL` 可指定环境 |
| 8 | 查空白 | `git diff --check` | 干净 |
| 9 | 脱敏 | 搜真实公司名 / 人名 / 单据号 / 内网域名 | 0 命中 |

> `predev` 与 `prebuild` 会自动跑 `scripts/generate-help.mjs` 和 `scripts/generate-demo.mjs`。
> 生成物（Excel、截图、`out/`、缓存、数据库）**都不入库**。

## 不可改动的契约

改动前逐条确认，这几条一动就等于换了一个产品：

| 契约 | 含义 |
| --- | --- |
| **七模块** | 业务分区固定，不新增或合并模块 |
| **稳定编号** | 记录编号稳定，不可重编 |
| **`schemaVersion=2`** | 数据格式版本，升级要走迁移 |
| **阶段历史** | 长期阶段历史保留，不可截断 |
| **冻结周报** | 已冻结的周报不可改写 |
| **Excel 逐项选版** | 导入冲突时逐项选版，不可改成整体覆盖 |
| **团队自选 ≠ 权限** | 自选团队只是业务分区，不是鉴权 |
| **归档只允许已完成项目** | 未完成项目不可归档 |
| **累计挽损包含归档** | 统计口径含归档数据 |
| **业务语义变更须用户明确要求** | 不自作主张改口径 |

## 改哪里

| 路径 | 放什么 | 注意 |
| --- | --- | --- |
| `next-app/components/audit/` | 业务界面 | 不放业务规则 |
| `next-app/lib/domain/` | 业务规则 | 改规则必须同步测试 |
| `next-app/lib/audit/` | Excel、存储、平台接口边界 | 平台适配只在这里 |
| `db/DDL/`、`db/sql/` | SQLite 结构与预定义 SQL | **不改写既有 DDL**；不会在前端自动建库 |
| `docs/使用说明.md` | 操作说明 | 由 `scripts/generate-help.mjs` 从同一内容源生成，不要手改产物 |
| `scripts/generate-demo.mjs` | 从虚构 JSON 生成示例 Excel | 生成文件不入库 |

## 数据模式（最容易踩的一条）

- 默认 `local-reference`：数据存在当前浏览器。
- 对接平台时**必须显式**设置 `NEXT_PUBLIC_DATA_MODE=platform`，挂载 `TeamWorkspace`，在业务边界适配数据调用。
- **platform 未配置时必须明确报错** —— 公开接口桩在未接入时直接报错，
  **绝不回退浏览器存储冒充共享保存**。
- 保存必须保留**团队与版本条件更新**（并发保护不能去掉）。
- 真实目标骨架与认证由目标项目负责，**不要在这里模拟"已接通"**。

## 常见失败怎么定位

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| `typecheck` 红 | 改了 `lib/domain` 的类型却没同步调用方 | 先修类型，不要用 `any` 绕过 |
| `npm test` 红但页面正常 | 业务口径变了而测试没跟着改（或反之） | 先判断是"测试对、代码错"还是"口径该改"，后者需用户明确要求 |
| `build` 红但 `dev` 正常 | `prebuild` 的生成脚本失败或缺文件 | 单独跑 `node scripts/generate-help.mjs` 看报错 |
| 部署后静态资源 404 | `NEXT_PUBLIC_BASE_PATH` 与实际挂载路径不一致 | 两者必须一致（如 `/audit-workbench`） |
| 平台模式下仍写浏览器 | 走了回退分支 | 删掉回退，必须显式报错 |

## 红线

- **不提交**：真实台账或规范、内部应用编号、私有接口、凭据、业务截图；生成的 Excel、截图、构建输出、缓存、数据库
- 只提交源码、必要使用文档、**虚构** JSON
- 保留第三方许可（`next-app/public/vendor/LICENSE.sheetjs.txt`）
- 不把"未验证"写成"已接通" —— 实际平台认证、跨客户端共享与部署均未在此公开项目验证
