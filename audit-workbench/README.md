# 稽核工作进度看板 · 工程演示版

独立于 [audit-kanban](../audit-kanban) 的 Next.js / React / TypeScript 工程。保留个人填报、Excel 预览汇总、经理查看、周报留档和备份的工作方式，增加团队分区、七类业务、长期阶段历史、挽损成果与分批明细、归档恢复、关注事项、快速更新、协作跟进和页面备注。

**公开演示：无真实业务数据、公司内部接口或登录实现。** 自选团队只是业务分区；默认数据保存在当前浏览器，各电脑不会自动同步。虚构示例仅用于交互演示。

## 运行

要求 Node.js 22.7+、npm；自动测试另需 Python 3。在本目录执行：

```sh
npm ci
npm run dev
```

打开 http://127.0.0.1:3000 。初始为空台账；使用说明中可下载自动生成的虚构 Excel 后导入。运行和构建使用本地 SheetJS，不依赖外部 CDN。

```sh
npm test
npm run build
npm run typecheck
```

构建输出 `next-app/out/`。可用 `python3 -m http.server 4179 --bind 127.0.0.1 --directory next-app/out` 本机预览。构建前可设置 `NEXT_PUBLIC_BASE_PATH=/audit-workbench`；部署时静态服务器须把输出挂载到同一路径。本项目需要构建，不是双击 HTML 的离线版。

浏览器回归脚本为 `tests/browser-dashboard.mjs`、`tests/browser-quick-notes.mjs`，运行需要 Playwright 与 Chrome，可通过 `PLAYWRIGHT_MODULE`、`AUDIT_TEST_URL`、`AUDIT_BROWSER_CHANNEL` 指定环境。测试只用隔离上下文与虚构数据。

## 维护与接入

- `next-app/components/audit/`：业务界面；`lib/domain/`：业务规则；`lib/audit/`：Excel、存储及平台接口边界。
- `db/DDL/` 与 `db/sql/`：通用 SQLite 数据结构和预定义 SQL；不会在前端自动创建服务器数据库。
- `docs/使用说明.md`：当前操作说明，由 `scripts/generate-help.mjs` 从同一内容源生成。
- `scripts/generate-demo.mjs`：从已声明虚构的 JSON 生成示例 Excel；生成文件不入库。

对接其他平台时，保留平台原有认证与构建流程，挂载 `TeamWorkspace`，在业务边界适配数据调用并显式设置 `NEXT_PUBLIC_DATA_MODE=platform`。公开接口桩在未接入时直接报错，绝不回退浏览器存储冒充共享保存。保存必须保留团队与版本条件更新；不要改写既有 DDL、阶段历史、稳定编号或 Excel 冲突选版规则。实际平台认证、跨客户端共享及部署尚未在此公开项目验证。

相比原版新增功能可直接在本机试用；原 `audit-kanban` 保持独立。只包含当前源码、测试和使用资料，不附开发过程或交付压缩包。SheetJS 许可见 `next-app/public/vendor/LICENSE.sheetjs.txt`。
