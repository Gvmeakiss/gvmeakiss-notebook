# 轻应用技术规范与实现指南（脱敏方法论版）

> **文档说明**：本文是一套企业内部「AI Agent 驱动的轻应用平台」技术规范的**脱敏整理版**，聚焦**架构方法论与实现逻辑**，供同类平台 / 轻应用设计与 AI 开发参考。
> **脱敏口径**：已隐去具体公司与内网标识——内部接口域名、服务名、平台名、请求头前缀、鉴权错误码等均已泛化（示例：`example.com`、`agent-platform`、`agent-bff`、`data-svc`、`InternalPortal`、`SSO`、`AUTH_401`）；接口路径结构（`/mini-app/*`）、架构分层、流程机制、代码约定均保留原貌。
> **适用范围**：企业内部基于 NAS + AI Agent 的轻量级 Web 应用平台（通用架构方法论）。
> **结构**：§0 TL;DR；§1 整体框架设计；§2 前端框架约定；§3 数据库管理方案；§4 生命周期控制方案；§5 接口清单汇总；§6 Agent 辅助开发约定；§7 依照本规范设计轻应用的标准流程（供 AI 调用参考）；附录 A 文件索引 / B 术语速查 / C 变更记录。

---

## 0. TL;DR（30 秒版）

- **本质**：AI Agent 驱动的静态 Web 应用开发与部署框架。前端 `Next.js 15` 静态导出 → NAS 挂载即可服务；所有数据走 BFF → Gateway → SQLite。
- **角色**：轻应用前端 / BFF 层 / Gateway 服务 / NAS 存储 / 数据库 / 开发沙箱 / Agent / 截图服务（共 8 类）。
- **关键概念**：`commit hash` 贯穿全生命周期（开发路径、产物、发布、回滚）；`basePath` 决定静态资源路径；`SQL 预定义` 杜绝前端拼接 SQL；`5 步脚本 + 3 级并发控制（mkdir 文件锁 + 30s 心跳 + 全局队列）` 保证发布零停机切换。
- **环境**：`本地 dev` / `开发预览 dev`（按 commit 预览） / `生产 prd` 三套 basePath 规则。
- **AI 开发约定**：`lib/client-fetch/`、`lib/service/`、`util/public.ts`、`next.config.ts` 为内置不可改模块；其余区域可自由开发。

---

## 1. 整体框架设计

### 1.1 设计理念

轻应用平台是一种 **AI Agent 驱动的静态 Web 应用开发与部署体系**，核心思路：

- **静态导出**：前端基于 Next.js 静态导出，无 Node.js 运行时，通过 NAS 挂载实现静态文件服务。
- **沙箱开发**：每个轻应用拥有独立的开发沙箱（含 NAS 挂载），Agent 在沙箱内完成代码生成与构建。
- **BFF 中介**：所有数据库访问、发布控制通过 BFF 层（Next.js API Routes，`agent-bff`）中转，前端不直接接触数据库。
- **版本化生命周期**：以 Git commit hash 为主轴，串联开发、预览、生产发布全流程。

### 1.2 系统角色

| 角色 | 说明 | 技术实现 |
|------|------|----------|
| 轻应用前端 | Next.js 15 静态导出应用，运行在浏览器 | Next.js + React 19 + Ant Design 6 |
| BFF 层 | 后端 API 层，负责数据库查询代理、发布流程控制 | Next.js API Routes（agent-bff） |
| Gateway 服务 | 企业网关，提供 NAS 路径解析、远程 SQL 执行等基础能力 | 内部微服务（/agent-platform/、/data-svc/） |
| NAS 存储 | 网络附加存储，存放源码、构建产物、数据库文件 | NAS 目录挂载 |
| 数据库 | 库文件（每个轻应用一个独立 SQLite 数据库） | SQLite（NAS 路径 `db/database.db`） |
| 开发沙箱 | 隔离的代码执行环境，挂载 NAS 路径供 Agent 开发 | 容器化沙箱 |
| Agent | AI 编码助手，在沙箱内进行代码生成、修改、构建 | AI Agent（算法侧） |
| 截图服务 | 对轻应用页面截图生成预览快照 | /screenshot-svc/screenshot |

### 1.3 整体架构图

```
用户浏览器
  ├── 轻应用前端（静态 HTML）  /mini-app/[appId]
  └── 管理端 / 预览端          /mini-app-dev/[appId]/[hash]
        │
        ▼  静态文件请求
静态文件服务（NAS 挂载）
  ├── {devRoot}/out-dev/[commitHash]/    ← 开发预览静态产物
  └── {prdRoot}/out-prd/                 ← 生产静态产物
  （NAS 根路径由 Gateway 接口动态返回，非固定规则目录）
  （注：{devRoot}/{prdRoot} 通过 getMiniAppNasRoot(appId, env) 获取）
        │
        ▼  HTTP API
BFF 层（agent-bff）
  ├── /mini-app/db                    SQL 查询代理
  ├── /mini-app/db-batch              批量 SQL 代理
  ├── /mini-app/config/publish/exec   发布
  └── /mini-app/config/route-list     路由列表
  （lib/db.ts：getSqlFilePath / loadSqlDefinition）
  （lib/mini-app-root-resolve.ts：getMiniAppNasRoot（LRU））
        │
        ▼
Gateway 服务（企业内部微服务）
  ├── /data-svc/sqlite/exeSql                   远程 SQLite 执行
  ├── /data-svc/sqlite/exeBatchSql              远程 SQLite 批量执行
  ├── /agent-platform/executePreDBSql            机构前置库查询
  └── /agent-platform/miniApp/getNasMappingPath  NAS 路径解析
        │
        ▼
NAS 存储层
  ├── {devRoot}/（开发环境 NAS 根路径）
  │   ├── next-app/            源代码（Git 仓库）
  │   ├── out-dev/[hash]/      开发构建产物
  │   └── db/                  开发环境 SQLite 数据库
  │       ├── DDL/             DDL 迁移脚本
  │       ├── sql/             预定义 SQL（*.sql.json）
  │       ├── database.db
  │       └── LAST_DDL_VERSION
  └── {prdRoot}/（生产环境 NAS 根路径）
      ├── out-prd/             生产构建产物
      └── db/                  生产环境 SQLite 数据库

开发沙箱（容器化）── NAS 挂载：/workspace/app → {devRoot}（由平台配置决定）
  └── Agent（AI）：源代码编辑 / bun install / build:dev / run-ddl.py

截图服务：/screenshot-svc/screenshot
```

### 1.4 核心数据流

#### 1.4.1 数据库查询数据流

```
[前端组件]
   │
   ▼
clientDBFetch({sqlFile, sqlKey, sqlParams})
   │
   ▼
clientFetchBff("/mini-app/db", POST)
   │
   ▼
BFF: getSqlFilePath(miniAppId, env, sqlFile)
   │
   ▼
getMiniAppNasRoot(appId, env)                          ── LRU 缓存
   │
   ▼
Gateway: /agent-platform/miniApp/getNasMappingPath     ── 返回 NAS 路径
   │
   ▼
[读取 NAS 上的 *.sql.json]
   │
   ▼
BFF: loadSqlDefinition({filePath})                     ── 加载 SQL 定义
   │
   ▼
BFF: execSqlRemote({appId, env, sql, sqlParams})
   │
   ▼
Gateway: /data-svc/sqlite/exeSql → 返回 {result, affectedRows}

clientDBBatchFetch(sqlList)
   │
   ▼
clientFetchBff("/mini-app/db-batch", POST)
   │
   ▼
BFF: 批量加载 SQL 定义（带缓存）→ execSqlBatchRemote
   │
   ▼
Gateway: /data-svc/sqlite/exeBatchSql
```

**关键设计**：SQL 定义文件存储在 NAS 上（而非 BFF 本地），BFF 通过 NAS 路径解析动态加载。修改 `db/sql/*.sql.json` 后无需重启 BFF。

#### 1.4.2 发布数据流

```
管理端触发发布（appId, commitHash）
   │
   ▼
GET /mini-app/config/publish/exec?appId=xxx&commitHash=yyy    ── SSE 流
   │
   ▼
tryAcquireLock(appId, commitHash)                             ── mkdir 原子锁
   │
   ▼
startHeartbeat(appId)                                         ── 30s 心跳，90s 超时
   │
   ▼
enqueueTask(...)                                              ── 全局队列，并发=1

发布任务执行：
  Step 1: check    ── git 状态校验 + rsync 复制源码到临时目录
  Step 2: install  ── bun install（生产环境配置）
  Step 3: build    ── bunx next build --turbopack（out-prd）
  Step 4: deploy   ── 复制产物 + 数据库 DDL 迁移 + 原子替换
  Step 5: cleanup  ── 清理 __prev 目录（异步）
```

### 1.5 环境模型

| 环境 | 标识 | basePath 规则 | NAS 路径 | 构建方式 |
|------|------|--------------|----------|----------|
| 本地开发 | `NEXT_PUBLIC_DEV_SERVER=1` | `/mini-app-dev/out`（固定） | 无（本地文件系统） | `bun run dev`（Turbopack dev server） |
| 开发预览 | `NEXT_PUBLIC_ENV=dev` | `/mini-app-dev/{appId}/{commitHash}` | `{devRoot}/out-dev/[commitHash]/` | `bun run build:dev`（沙箱内） |
| 生产 | `NEXT_PUBLIC_ENV=prd` | `/mini-app/{appId}` | `{prdRoot}/out-prd/` | 服务器执行 step-1~5 脚本 |

注：`{devRoot}` / `{prdRoot}` 不是固定路径，由 BFF 通过 `getMiniAppNasRoot(appId, env)` 调用 Gateway 接口 `/agent-platform/miniApp/getNasMappingPath` 动态获取。

### 1.6 关键设计决策

1. **静态导出而非 SSR**：轻应用无 Node.js 运行时，降低运维复杂度，NAS 挂载即可服务。
2. **SQL 预定义而非动态拼接**：所有业务 SQL 以 `*.sql.json` 形式定义在 `db/sql/` 目录，前端通过 `sqlFile + sqlKey` 引用，BFF 层加载并转发——避免 SQL 注入，实现 SQL 与代码解耦。
3. **commitHash 作为版本主轴**：开发预览路径、构建产物目录、发布锁定均以 commit hash 标识，确保版本可追溯。
4. **文件锁 + 心跳 + 队列三级并发控制**：发布流程通过 mkdir 原子锁（防并发）、心跳守护（防僵尸锁）、全局队列（串行化）三层保障。
5. **原子替换部署**：生产部署使用 `__next → 替换 → __prev → 清理` 模式，确保零停机切换。

---

## 2. 轻应用前端框架约定

### 2.1 Monorepo 结构

轻应用采用 **Bun Monorepo** 结构，样板代码仓库 `mini-app-skeleton` 包含两个工作区：

```
/
├── package.json              # 根 package.json（工作区配置 + 构建脚本）
├── bun.lock                  # Bun 锁文件
├── build-dev.sh              # 开发环境构建脚本
├── next-app/                 # Next.js 前端项目（工作区）
│   ├── app/                  # App Router 页面
│   │   ├── layout.tsx        # 根布局
│   │   ├── page.tsx          # 首页
│   │   └── login/            # 登录页
│   ├── components/           # 共享 React 组件
│   ├── lib/                  # 核心库代码
│   │   ├── client-fetch/     # HTTP 请求封装（内置，勿改动）
│   │   ├── components/       # 基础 UI 组件
│   │   ├── const/            # 常量和枚举
│   │   ├── event/            # 全局事件总线
│   │   ├── provider/         # React Context Provider
│   │   ├── query/            # React Query 封装
│   │   ├── service/          # 配置管理（内置，勿改动）
│   │   ├── store/            # Zustand 状态管理
│   │   └── types/            # TypeScript 类型定义
│   ├── types/                # 全局类型定义
│   ├── util/                 # 工具函数
│   │   └── public.ts         # $static 静态资源函数（内置，勿改动）
│   ├── skills/               # Agent 技能
│   ├── public/               # 静态资源
│   ├── next.config.ts        # Next.js 配置（内置，勿改动）
│   ├── tsconfig.json         # TypeScript 配置
│   └── package.json
└── db/                       # 数据库管理目录（工作区）
    ├── DDL/                  # DDL 迁移脚本
    ├── sql/                  # 预定义 SQL（*.sql.json）
    ├── run-ddl.py            # DDL 执行脚本
    ├── database.db           # SQLite 数据库文件（.gitignore）
    ├── LAST_DDL_VERSION      # DDL 版本记录（.gitignore）
    └── .DDLFILES             # DDL 文件列表
```

### 2.2 技术栈

| 类别 | 技术 | 版本 |
|------|------|------|
| 前端框架 | Next.js（App Router） | 15.5 |
| UI 框架 | React | 19.1 |
| 类型系统 | TypeScript（strict） | 5 |
| UI 组件库 | Ant Design | 6.3 |
| CSS 方案 | Tailwind CSS + Sass | 5 / 5.90 |
| 状态管理 | Zustand（客户端）+ React Query（服务端） | - |
| HTTP 请求 | 封装 fetch（内置 `clientFetch`） | - |
| 事件系统 | 基于 CustomEvent 的全局事件总线 | - |
| 包管理器 | Bun（Monorepo 工作区） | - |
| 构建工具 | Turbopack（dev）/ Next.js build（prd） | - |
| 测试框架 | Vitest | - |

### 2.3 配置体系

#### 2.3.1 环境变量

| 变量名 | 说明 | 使用场景 |
|--------|------|----------|
| `NEXT_PUBLIC_ENV` | 构建环境标识：`dev` / `prd` | 决定 basePath 规则和 distDir |
| `NEXT_PUBLIC_APP_ID` | 轻应用 ID | 构建 basePath、数据库查询 appId |
| `NEXT_PUBLIC_APP_GIT_HASH` | Git commit hash（完整） | 开发环境构建 basePath |
| `NEXT_PUBLIC_DEV_SERVER` | 是否启用开发服务器代理（1） | 仅本地 `next dev` |

#### 2.3.2 静态配置（`lib/service/static-config.ts`，内置勿改动）

根据环境变量动态计算 `APP_BASE_URL`（即 Next.js `basePath`）：

```ts
// 开发环境：/mini-app-dev/{appId}/{commitHash}
// 生产环境：/mini-app/{appId}
APP_BASE_URL =
  ENV === "dev"
    ? `/mini-app-dev/${APP_ID}/${APP_GIT_VER}`
    : `/mini-app/${APP_ID}`;
```

注：`APP_GIT_VER` 对应环境变量 `NEXT_PUBLIC_APP_GIT_HASH`（完整 commit hash）。

#### 2.3.3 动态配置（`lib/service/dynamic-config.ts`，内置勿改动）

运行时从浏览环境动态获取的配置：

- `getAppEntry()`：从 UserAgent 判断入口平台（Web / InternalPortal PC）
- `getSSOToken()`：按入口平台返回对应的 SSO Token
- `getDeployEnv()`：从域名判断部署环境（STG / PRD）
- `getOrigin()`：获取 API 请求基础域名
- `getLoginUrl()`：获取 SSO 登录 URL

#### 2.3.4 Next.js 配置（`next.config.ts`，内置勿改动）

```ts
{
  // 静态导出
  output: "export",
  // dev: out（构建后移动到 out-dev/{commitHash}/）；prd: out-prd
  distDir: ENV === "prd" ? "out-prd" : "out",
  // 自动配置 basePath
  basePath: APP_BASE_URL,
  compress: false,
  typescript: { ignoreBuildErrors: true },
  productionBrowserSourceMaps: ENV === "dev",
  // 仅 NEXT_PUBLIC_DEV_SERVER=1 时配置 API 代理
  rewrites: [],
}
```

### 2.4 请求层架构（`lib/client-fetch/`，内置勿改动）

#### 2.4.1 请求层结构

| 文件 | 说明 |
|------|------|
| `client-fetch.ts` | 基础请求方法 + Gateway/BFF 派生方法 |
| `client-db-fetch.ts` | 轻应用 SQLite 查询封装 |
| `client-db-batch-fetch.ts` | 轻应用 SQLite 批量查询封装 |
| `client-pre-db-fetch.ts` | 机构前置库查询封装 |
| `client-sso-api-fetch.ts` | SSO API 查询封装 |

#### 2.4.2 请求链路

```
clientFetch（基础方法）
 ├─ 自动注入请求头：x-sso-token, x-app-source, x-user-id
 └─ 登录过期检测：HTTP 401 或业务错误码 AUTH_401/AUTH_EXPIRED
     └→ emitGlobalEvent("login-error")

clientFetchGateway(url)
 ├─ 路径前缀：/gateway
 ├─ 请求头：x-service-target: gateway
 └─ 本地开发时通过 APP_BASE_URL 前缀走 Next.js rewrite 代理

clientFetchBff(url)
 ├─ 路径前缀：/agent-platform/bff
 ├─ 请求头：x-service-target: bff
 └─ 本地开发时通过 APP_BASE_URL 前缀走 Next.js rewrite 代理

checkResponse(res)
 └─ 检查 res.code === 200，否则抛出
```

#### 2.4.3 数据库查询封装

**单条查询** → `clientDBFetch`：

```ts
interface DBFetchPayload {
  sqlFile: string;        // 如 "example_users.sql.json"
  sqlKey: string;         // 如 "getPage"
  sqlParams: unknown[];   // 按 ? 占位符顺序
}
// 调用 BFF: POST /mini-app/db
// BFF 从 NAS 加载 sqlFile → 取 sqlKey 对应 SQL → 转发 Gateway 执行
```

**批量查询** → `clientDBBatchFetch`：

```ts
// 调用 BFF: POST /mini-app/db-batch
// 支持混合增删改查，返回每个 SQL 的独立结果
interface DBBatchFetchResponse {
  code: number;
  data: {
    results: Array<{
      result: unknown[];      // SELECT 结果
      affectedRows: number;   // 影响行数
      error?: string;         // 单条失败原因
    }>;
    successCount: number;
    failureCount: number;
    allSuccess: boolean;
  } | null;
}
```

**机构前置查询** → `clientPreDBFetch`：

1. 直接调用 Gateway：`POST /gateway/agent-platform/executePreDBSql`
2. 仅支持查询（SELECT），不支持写操作
3. `sqlId` / `sql` 从 `pre-db-api/api.json` 取值，禁止修改 SQL

### 2.5 静态资源访问约定

所有 `public/` 目录下的资源必须使用 `$static()` 函数，适用范围：`<img>`、`<Image>`、`<script>`、`<Link>` 等所有 public/ 资源引用。

```tsx
import { $static } from '@/util/public';

// $static(path) 实现：return APP_BASE_URL + path

// ✓ 正确：自动拼接 APP_BASE_URL
<img src={$static('/assets/logo.svg')} alt="logo" />

// × 错误：因 basePath 存在，直接路径会 404
<img src="/assets/logo.svg" alt="logo" />
```

### 2.6 路径别名

使用 `@/` 作为 `next-app/` 根目录别名（`tsconfig.json` 配置）：

```ts
import { useAuthStore } from '@/lib/store/useAuthStore';
import { clientDBFetch } from '@/lib/client-fetch/client-db-fetch';
```

### 2.7 认证与权限约定

- **登录态检测**：`clientFetch` 自动检测 HTTP 401 或业务错误码 `AUTH_401/AUTH_EXPIRED`，触发 `login-error` 事件
- **权限检查**：`useAuthStore.hasPermission(permission)` 检查功能权限
- **路由控制**：`useAuthStore.canAccessRoutePath(path)` 检查可访问路由
- **状态管理**：`useAuthStore`（Zustand）存储用户信息和菜单列表
- **Cookie 域名**：本地开发必须使用 `localhost.example.com` 访问（通过修改 hosts），以读取 `.example.com` 域下登录态

### 2.8 全局事件系统

基于浏览器的 `CustomEvent` 的跨组件通信机制：

```ts
import { emitGlobalEvent, useEventListener } from '@/lib/event';

// 监听
const unsubscribe = useEventListener("login-error", (event) => {
  // 处理登录过期
});

// 发射
emitGlobalEvent("login-error", { httpStatus: 401 });
```

### 2.9 代码质量约定

- **ESLint**：配置在 `eslint.config.mjs`
- **Git Hooks**：Husky + lint-staged，提交时自动 ESLint 修复
- **TypeScript**：严格模式 `strict: true`
- **包管理器锁定**：`preinstall: bunx only-allow bun` 强制使用 Bun

### 2.10 内置模块约定（Agent 开发时不修改）

以下文件标记为 `/* 内置组件请勿改动 */`，Agent 开发时不允许修改：

| 文件 | 说明 |
|------|------|
| `lib/client-fetch/client-fetch.ts` | 基础请求方法 |
| `lib/client-fetch/client-db-fetch.ts` | 数据库查询封装 |
| `lib/client-fetch/client-db-batch-fetch.ts` | 数据库批量查询封装 |
| `lib/client-fetch/client-pre-db-fetch.ts` | 前置库查询封装 |
| `lib/service/static-config.ts` | 静态配置 |
| `lib/service/dynamic-config.ts` | 动态配置 |
| `util/public.ts` | `$static` 函数 |
| `next.config.ts` | Next.js 配置 |

---

## 3. 数据库管理方案

### 3.1 数据库架构

每个轻应用拥有独立的 SQLite 数据库，数据库文件存储在 NAS 路径 `db/database.db` 中，通过 BFF 层代理访问。

```
db/                                    # 数据库管理目录（工作区）
├── DDL/
│   ├── v1.create-table-xxx.sql        # 创建表
│   ├── v2.init-table-xxx.sql          # 初始化数据
│   └── ...                            # DDL 迁移脚本（版本化）
├── sql/
│   ├── example_users.sql.json         # 预定义业务 SQL
│   └── ...                            # { key: "SQL with ? params" }
├── run-ddl.py                         # DDL 执行脚本
├── database.db                        # SQLite 数据库文件（.gitignore）
├── LAST_DDL_VERSION                   # DDL 版本记录（.gitignore）
└── .DDLFILES                          # DDL 文件列表
```

### 3.2 DDL 版本控制

#### 3.2.1 命名规则

- **格式**：`v[版本号].[描述].sql`
- **版本号**：非负整数，从 1 开始严格递增（`v1, v2, v3...`）
- **描述**：小写字母 + 连字符（如 `create-table-users`）

#### 3.2.2 执行机制（`run-ddl.py`）

1. 首次执行时重置数据库（删除已有 `database.db`）
2. 扫描 `DDL/` 目录，按版本号数字排序
3. 读取 `LAST_DDL_VERSION`，对比找出新版本
4. 增量执行新脚本（`executescript`，支持多语句）
5. 每个脚本成功后更新 `LAST_DDL_VERSION`
6. 失败时停止并记录最后成功版本
7. 执行完毕后修改 `database.db` 权限为 `602:602`

#### 3.2.3 DDL 规范

- **版本递增**：版本号必须严格递增，不可重复或跳跃
- **不可修改**：提交后的 DDL 文件不允许二次改动
- **幂等性**：使用 `CREATE TABLE IF NOT EXISTS` 等幂等语法
- **多语句支持**：一个文件可包含多条 SQL 语句

### 3.3 预定义 SQL

业务 SQL 以 JSON 格式存储在 `db/sql/*.sql.json` 中：

```json
{
  "getPage": "SELECT * FROM example_users WHERE user_name LIKE ? LIMIT ? OFFSET ?",
  "insert":  "INSERT INTO example_users (id, user_name, department_name, department_code) VALUES (?, ?, ?, ?)",
  "update":  "UPDATE example_users SET user_name = ?, department_name = ?, department_code = ? WHERE id = ?",
  "delete":  "DELETE FROM example_users WHERE id = ?"
}
```

- **key**：业务标识，前端通过 `sqlKey` 引用
- **参数化查询**：使用 `?` 占位符，参数通过 `sqlParams` 数组按顺序传入
- **防注入**：BFF 层加载 SQL 定义后原样转发至 Gateway 执行，前端无法动态修改 SQL

### 3.4 数据库访问链路

```
前端 clientDBFetch
   │
   ▼
BFF: POST /mini-app/db
   │
   ▼
getSqlFilePath(appId, env, sqlFile)
   │
   ▼
getMiniAppNasRoot(appId, env) [LRU 缓存 30min]
   │
   ▼
Gateway: /agent-platform/miniApp/getNasMappingPath
   │
   ▼
返回：{nasRoot}/db/sql/{sqlFile}  [读取 *.sql.json]
   │
   ▼
loadSqlDefinition(filePath) [读取 *.sql.json]
   │
   ▼
execSqlRemote({appId, env, sql, sqlParams})
   │
   ▼
Gateway: /data-svc/sqlite/exeSql → 返回 SQLite 执行结果
```

**关键设计**：SQL 定义文件存储在 NAS 上（而非 BFF 本地），BFF 通过 NAS 路径解析动态加载。这意味着修改 `db/sql/*.sql.json` 后无需重启 BFF。

### 3.5 批量查询

BFF `/mini-app/db-batch` 接口支持批量执行多条预定义 SQL：

- 使用 `sqlCache`（Map）缓存同一请求中重复引用的 SQL 定义文件
- 逐条加载 → 逐条校验 `sqlKey` → 批量转发至 Gateway `exeBatchSql`
- 返回每条 SQL 的独立结果（成功/失败、`result`、`affectedRows`）

---

## 4. 生命周期控制方案（工程侧）

### 4.1 生命周期总览

轻应用从创建到最终发布的完整生命周期分为 **6 个阶段**：

```
创建 → 开发 → 开发构建预览 → 发布 → 生产部署 → 清理

并发控制：文件锁 + 心跳 + 队列
```

### 4.2 阶段一：应用创建

1. 复制 `mini-app-skeleton` 样板代码到 NAS 路径 `{devRoot}/`
2. 初始化本地 Git 仓库
3. 配置 `NEXT_PUBLIC_APP_ID` 等环境变量
4. 执行 `bun install` 安装依赖
5. 执行 `python3 db/run-ddl.py` 初始化数据库

（`{devRoot}` 由平台为该 appId 分配，BFF 通过 Gateway 接口动态获取）

NAS 目录结构（开发环境，根路径 `{devRoot}` 由 Gateway 接口返回）：

```
{devRoot}/
├── next-app/                    # 源代码
│   └── out-dev/
│       └── [commitHash]/        # 开发构建产物（按完整 commit hash 组织）
├── db/                          # 开发数据库
│   ├── DDL/
│   ├── sql/
│   ├── database.db
│   └── LAST_DDL_VERSION
└── .git/
```

### 4.3 阶段二：沙箱开发

1. 挂载 NAS 路径到沙箱：`/workspace/app → {devRoot}`（由平台按 appId 分配）
2. Agent 在沙箱内进行代码生成与修改
3. 可执行 `python3 db/run-ddl.py` 更新开发数据库 Schema
4. 通过 Git 提交代码变更

沙箱内的 NAS 路径映射：

- 沙箱路径：`/workspace/app`
- 服务器 NAS 路径：`{devRoot}/`（由平台按 appId 分配，BFF 通过 Gateway 接口动态获取）

### 4.4 阶段三：开发构建预览

通过 `bun run build:dev`（根目录执行 `build-dev.sh`）在沙箱内完成开发环境构建。

#### 4.4.1 build-dev.sh 执行流程

1. `git safe.directory` 配置
2. 检查工作区是否干净（有未提交更改则报错退出）
3. 获取当前 commit hash
4. 更新 `db/.DDLFILES`（DDL 文件列表）
5. 如有文件变更（如 `.DDLFILES`），自动提交
6. 检查 `bun.lock` 是否变化 → 决定是否执行 `bun install`
7. 设置环境变量：
   - `NEXT_PUBLIC_DEV_SERVER=0`
   - `NEXT_PUBLIC_ENV=dev`
   - `NEXT_PUBLIC_APP_GIT_HASH={commitHash}`
8. 执行 `bunx next build --turbopack`
9. 移动产物：`next-app/out` → `out-dev/{commitHash}/`
10. 复制 `routes-manifest.json` 到产物目录

#### 4.4.2 预览访问

`basePath` 自动计算为 `/mini-app-dev/{appId}/{commitHash}`

URL：`/mini-app-dev/[appId]/[commitHash]`

#### 4.4.3 路由列表查询

BFF 提供路由列表接口，供管理端获取轻应用可用页面：

```
1. GET /mini-app/config/route-list?appId=xxx&commitHash=yyy
2. → 读取 out-dev/{commitHash}/routes-manifest.json
3. → 返回 staticRoutes + dynamicRoutes（过滤系统路由）
```

### 4.5 阶段四：发布流程

#### 4.5.1 发布接口

```
GET /mini-app/config/publish/exec?appId=xxx&commitHash=yyy
  → SSE 流式响应
```

**SSE 事件类型**：

| 事件 | 数据 | 说明 |
|------|------|------|
| `connected` | `{}` | 连接建立 |
| `log` | `{text: string}` | 日志输出 |
| `step` | `{step: number, stepAct: string, stepStatus: string}` | 步骤进度 |
| `ping` | `{code: number, msg: string}` | 心跳保活（30s） |
| `end` | `{}` | 发布结束 |

**日志协议**：日志文本以 `<步骤号>[级别] 内容` 格式输出，BFF 自动解析为 `step` 事件。

#### 4.5.2 并发控制机制

发布流程采用 **三级并发控制**：

**第一级：文件锁（mkdir 原子操作）**

```
1. tryAcquireLock(appId, commitHash)
   → 锁目录：/application/agent-platform/publish-lock/mini-app-prd/{appId}/.publish_lock/
   → 使用 mkdir 原子性创建锁目录
2. → 写入 info.json：{commitHash, taskStatus, pid, hostname, startTime, lastHeartbeat, timeout}
3. timeout: 90 秒
```

**锁状态处理逻辑**：

| 场景 | 处理 |
|------|------|
| 锁不存在 | 获取锁，开始发布 |
| 锁存在 + commitHash 相同 | 重放 SSE 日志（支持断线重连） |
| 锁存在 + commitHash 不同 | 拒绝："另一个版本的发布任务正在执行中" |
| 锁存在 + 已过期（stale） | 释放旧锁，重新获取 |
| 锁存在 + 未过期 + 不同 commitHash | 拒绝并等待 |

**第二级：心跳守护**

```
1. startHeartbeat(appId)
2. → 每 30 秒更新 lastHeartbeat
3. → 心跳超时：90 秒（HEARTBEAT_TIMEOUT = 1.5min）
4. → 超时后锁被视为 stale，可被其他请求抢占
```

**第三级：全局任务队列**

```
1. publishTaskQueue（concurrency: 1）
2. → 同一时刻仅执行一个发布任务
3. → 排队中发送排队位置通知
4. → 出队时检查锁的 commitHash 是否一致（不一致则跳过-取消）
5. → 总超时：20 分钟
```

#### 4.5.3 SSE 日志持久化与重放

**发布执行时**：

1. 每条 SSE 事件同时写入文件：`{lockDir}/{appId}/.publish_sse_{commitHash}.log`

**断线重连时**：

```
1. GET /mini-app/config/publish/query?appId=xxx
2. → 读取锁信息获取 commitHash
3. → replayPublishSSE: tail 文件从头重放
4. → 遇到 event:end 则停止
```

**发布成功后**：延迟 2 分钟清理 SSE 日志文件。

#### 4.5.4 截图快照

发布前/后可获取轻应用预览截图：

```
1. GET /mini-app/config/fetch-snapshot?appId=xxx&commitHash=yyy
2. → 调用截图服务：POST /screenshot-svc/screenshot
3. → url：/mini-app-dev/{appId}/{commitHash}?supress_login_error=1
4. → width: 1280, height: 720
5. → 返回 1005 截图链接
6. → 超时：5 分钟
```

### 4.6 阶段五：生产部署（5 步脚本）

发布任务执行 5 个步骤脚本，位于 `app/bff/mini-app/config/publish/steps/`。

#### 4.6.1 环境变量传递

BFF 向步骤脚本注入以下环境变量：

| 变量 | 说明 |
|------|------|
| `NODE_ENV` | `production` |
| `NEXT_PUBLIC_APP_ID` | 轻应用 ID |
| `NEXT_PUBLIC_APP_GIT_HASH` | 发布的 commit hash |
| `BUILD_DIR` | 临时构建目录 `/tmp/mini-app-build/{appId}_{commitHash}_{timestamp}` |
| `DEV_NAS_DIR` | 开发环境 NAS 根路径 |
| `PRD_NAS_DIR` | 生产环境 NAS 根路径 |
| `npm_config_registry` | 内部 npm registry |

#### 4.6.2 Step 1：检查（`step-1-check.sh`）

1. 校验环境变量（`APP_ID, APP_GIT_HASH, DEV_NAS_DIR`）
2. `cd $DEV_NAS_DIR`
3. `git safe.directory` 配置
4. 校验 `git HEAD == commitHash`（必须一致）
5. 如有未提交更改 → `git stash`（退出时恢复）
6. 解析 `.gitignore` 构建 rsync 排除列表
7. `rsync` 源码 → `$BUILD_DIR`（排除 `node_modules`、`.git` 等）
8. 强制包含 `next-app/config/` 目录（即使被 `.gitignore` 误伤）
9. 同步 `db/DDL/` 目录到 `$BUILD_DIR`

**关键点**：发布要求 commit hash 一致且工作区干净（或可 stash），确保发布的代码是已提交版本。

#### 4.6.3 Step 2：安装依赖（`step-2-install.sh`）

1. 设置生产环境变量：
   - `FROM_SERVER_BUILD=1`
   - `NEXT_PUBLIC_DEV_SERVER=0`
   - `NEXT_PUBLIC_ENV=prd`
2. 移除所有 `package.json` 中的 `preinstall` 脚本（避免 only-allow bun 检查）
3. `cd $BUILD_DIR && bun install`

**重试机制**：退出码 `137`（OOM 被 kill）时自动重试，最多 5 次，间隔 2 秒。

#### 4.6.4 Step 3：构建（`step-3-build.sh`）

1. `cd $BUILD_DIR/next-app`
2. `bunx next build --turbopack`
3. 验证 `out-prd` 目录存在

**重试机制**：同 Step 2，退出码 137 重试。

#### 4.6.5 Step 4：部署（`step-4-deploy.sh`）

部署采用 **原子替换策略**：

1. **复制构建产物**：
   - `$BUILD_DIR/next-app/out-prd` → `$PRD_NAS_DIR/out-prd__next`
2. **数据库迁移**：
   - a. 复制现有生产数据库到构建目录：`$PRD_NAS_DIR/db/database.db` → `$BUILD_DIR/db/`
   - b. 复制 `LAST_DDL_VERSION`
   - c. 执行 `python3 run-ddl.py`（增量迁移）
   - d. 准备新 db 目录：`$BUILD_DIR/db` → `$PRD_NAS_DIR/db__next`
3. **原子替换静态文件**：
   - a. 现有 `out-prd` → `out-prd__prev`（备份）
   - b. `out-prd__next` → `out-prd`（替换）
4. **原子替换数据库目录**：
   - a. 现有 `db` → `db__prev`（备份）
   - b. `db__next` → `db`（替换）
5. **修改数据库权限**：`chown 602:602, chmod 777`

**重试机制**：同 Step 2，退出码 137 重试。

**关键设计**：

- 数据库迁移在构建目录中执行（基于生产现有数据增量迁移），而非直接操作生产数据库
- 双写 `__next` - 原子 mv 替换，确保切换瞬间一致
- `__prev` 保留用于回滚

#### 4.6.6 Step 5：清理（`step-5-cleanup.sh`）

1. 删除 `$PRD_NAS_DIR/out-prd__prev`
2. 删除 `$PRD_NAS_DIR/db__prev`
3. 删除临时构建目录 `$BUILD_DIR`（异步）

**执行方式**：异步执行（`setTimeout 500ms`），不阻塞发布完成通知。清理失败仅 warn 不影响发布结果。

#### 4.6.7 步骤超时与重试

| 参数 | 值 | 说明 |
|------|------|------|
| `STEP_TIMEOUT` | 10 分钟 | 单步骤超时 |
| `TOTAL_TIMEOUT` | 20 分钟 | 发布总超时 |
| 重试次数 | 5 次 | 仅退出码 137 重试 |
| 重试间隔 | 2 秒 | — |

#### 4.6.8 生产访问

```
URL:      /mini-app/[appId]
basePath: /mini-app/{appId}
NAS:      {prdRoot}/out-prd/
```

（`{prdRoot}` 由 `getMiniAppNasRoot` 动态获取）

### 4.7 NAS 路径解析

轻应用的 NAS 根路径不是固定规则的目录，BFF 无法自行推算，必须通过 Gateway 接口按 `appId + env` 动态获取：

```
1. getMiniAppNasRoot(appId, env)
2. → Gateway: GET /agent-platform/miniApp/getNasMappingPath?appId=xxx&env=yyy
3. → 返回：{path}（由平台后端按 appId 分配的具体 NAS 路径，无固定规则）
4. → LRU 缓存：max=5000, ttl=30min, updateAgeOnGet=true
```

**重要**：BFF 层所有需要访问 NAS 文件的操作（加载 SQL 定义、发布时复制源码/产物、读取 routes-manifest 等）都先通过此接口获取根路径。本地开发时通过环境变量 `MINI_APP_LOCAL_DEV_DIR` 直接指定，不走 Gateway。

### 4.8 生产环境 NAS 结构

以下结构基于 `{prdRoot}`（由 `getMiniAppNasRoot(appId, "prd")` 动态返回的根路径）：

```
{prdRoot}/
├── out-prd/                  # 生产静态产物（当前版本）
├── out-prd__prev/            # 上一版本（发布后短暂保留，清理后删除）
├── out-prd__next/            # 下一版本（部署过程中短暂存在）
├── db/                       # 生产数据库（当前版本）
│   ├── DDL/
│   ├── sql/
│   ├── database.db
│   ├── LAST_DDL_VERSION
│   └── run-ddl.py
├── db__prev/                 # 上一版本数据库
└── db__next/                 # 下一版本数据库（部署过程中短暂存在）
```

### 4.9 发布锁文件结构

```
/application/agent-platform/publish-lock/mini-app-prd/
└── [appId]/
    ├── .publish_lock/                  # 锁目录（mkdir 原子创建）
    │   └── info.json                   # 锁信息
    └── .publish_sse_[commitHash].log   # SSE 日志文件
```

**info.json 结构**：

```json
{
  "commitHash": "abc123...",
  "taskStatus": "running", // "queued" | "running"
  "pid": 12345,
  "hostname": "server-01",
  "startTime": 1690000000000,
  "lastHeartbeat": 1690000030000,
  "timeout": 90000 // 90 秒
}
```

### 4.10 生命周期时序图

```
时间 →
创建：[复制样板] → [git init] → [bun install] → [run-ddl.py]
                                                        │
开发：                                    [Agent编码] → [git commit]
                                                        │
预览：                          [预览访问] ← [build:dev] → [out-dev/{hash}]
                                                        │
发布：[发布请求]
        ├→ tryAcquireLock（获取锁）
        ├→ startHeartbeat（心跳启动）
        ├→ enqueueTask（入队）
        ├→ Step1: check   ── git校验 + rsync
        ├→ Step2: install ── bun install
        ├→ Step3: build   ── next build
        ├→ Step4: deploy  ── 复制产物 + DDL迁移 + 原子替换
        ├→ Step5: cleanup（异步）── 清理 __prev
        ├→ releaseLock
        └→ SSE end: {code:200}
                                                        │
生产：[访问 /mini-app/{appId}]
```

---

## 5. 接口清单汇总

### 5.1 BFF 接口

| 方法 | 路径 | 说明 | 响应类型 |
|------|------|------|----------|
| POST | `/mini-app/db` | 执行单条预定义 SQL | JSON |
| POST | `/mini-app/db-batch` | 批量执行预定义 SQL | JSON |
| GET | `/mini-app/config/publish/exec` | 发布轻应用 | SSE |
| GET | `/mini-app/config/publish/query` | 查询发布状态（重放日志） | SSE |
| GET | `/mini-app/config/fetch-snapshot` | 获取应用截图 | JSON |
| GET | `/mini-app/config/route-list` | 获取路由列表 | JSON |

### 5.2 Gateway 接口（BFF 调用）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/agent-platform/miniApp/getNasMappingPath` | 获取 NAS 路径 |
| POST | `/data-svc/sqlite/exeSql` | 远程 SQLite 执行 |
| POST | `/data-svc/sqlite/exeBatchSql` | 远程 SQLite 批量执行 |
| POST | `/agent-platform/executePreDBSql` | 机构前置库查询 |

### 5.3 前端请求封装

| 方法 | 目标 | 路径前缀 |
|------|------|----------|
| `clientFetch` | 基础请求 | — |
| `clientFetchGateway` | Gateway 服务 | `/gateway` |
| `clientFetchGatewayPostJson` | Gateway 服务（POST JSON） | `/gateway` |
| `clientFetchBff` | BFF 服务 | `/agent-platform/bff` |
| `clientDBFetch` | 轻应用数据库 | `/agent-platform/bff/mini-app/db` |
| `clientDBBatchFetch` | 轻应用数据库（批量） | `/agent-platform/bff/mini-app/db-batch` |
| `clientPreDBFetch` | 机构前置库 | `/gateway/agent-platform/executePreDBSql` |

---

## 6. Agent 辅助开发的基础约束（预备章节）

本节为后续「AGENT 辅助开发流程设计」文档的基础输入，描述 Agent 需遵守的框架约束。

### 6.1 Agent 可操作范围

| 区域 | 可操作 | 不可操作 |
|------|--------|----------|
| `next-app/app/` | 页面开发 | — |
| `next-app/components/` | 组件开发 | — |
| `next-app/lib/query/` | React Query | — |
| `next-app/lib/const/` | 常量枚举 | — |
| `next-app/lib/types/` | 类型定义 | — |
| `next-app/lib/store/` | 状态管理 | — |
| `next-app/lib/provider/` | Provider | — |
| `next-app/lib/components/` | 基础 UI 组件 | — |
| `next-app/lib/client-fetch/` | — | × 内置勿改动 |
| `next-app/lib/service/` | — | × 内置勿改动 |
| `next-app/util/public.ts` | — | × 内置勿改动 |
| `next-app/next.config.ts` | — | × 内置勿改动 |
| `db/DDL/` | 新增 DDL 脚本 | × 修改已有脚本 |
| `db/sql/` | 新增/修改 SQL 定义 | — |
| `db/run-ddl.py` | — | × 勿改动 |
| `package.json`（根/next-app） | 新增依赖 | × 修改内置脚本 |

### 6.2 Agent 开发工作流

1. 接收需求 → 理解轻应用骨架结构
2. 页面/组件开发 → 遵循 `$static`、`@/` 别名等约定
3. 数据库开发 → DDL 增量脚本 + SQL 预定义
4. 数据库查询 → 使用 `clientDBFetch` / `clientDBBatchFetch`
5. 提交代码 → `git commit`（工作区必须干净）
6. 开发构建 → `bun run build:dev`
7. 预览验证 → `/mini-app-dev/{appId}/{commitHash}`

### 6.3 Agent 需理解的关键概念

1. **basePath 机制**：所有静态资源和路由都受 basePath 影响，必须使用 `$static()`
2. **SQL 预定义模式**：不能在代码中写 SQL 字符串，必须通过 `db/sql/*.sql.json` 定义
3. **DDL 不可逆**：已提交的 DDL 脚本不能修改，只能新增版本
4. **commitHash 关联**：构建产物路径、预览路径、发布锁定都以 commitHash 为标识
5. **构建前提**：`build:dev` 要求工作区干净（无未提交更改）

---

## 7. 依照本规范设计轻应用（标准流程，供 AI 调用参考）

> 本章为整理时追加（原文档不含），专门为后续 AI 调用而设计。当接到「设计一个轻应用」需求时，按以下流程严格执行。

### 7.1 AI 接到需求时的标准输入清单

接到需求后，必须先问清/确认以下信息（缺一项就要问）：

| # | 项目 | 说明 | 示例 |
|---|------|------|------|
| 1 | appId | 唯一标识（决定 NAS 路径） | `audit-checklist-2026` |
| 2 | 应用名 | 中文/英文展示名 | 「审计底稿清单核查」 |
| 3 | 业务场景 | 一句话说清业务目标 | 用于 XX 部门对 XX 业务的 XX 控制点进行测试 |
| 4 | 页面清单 | 需要哪些页面（页面名 + 主要内容） | 首页（列表）、详情页、登录页 |
| 5 | 数据表清单 | 需要哪些数据表（字段 + 关系） | users(id, name, dept_id)、departments(id, name) |
| 6 | SQL 清单 | 预定义 SQL 列表（业务名 + 参数 + 返回） | `getUserList(deptId) → users[]` |
| 7 | 鉴权要求 | 是否需登录、是否需功能权限 | 需登录；需 menu_perm 含 `audit.checklist` |
| 8 | SSO / 前置库 | 是否需调用机构前置库 | 是 → sqlId/参数 |
| 9 | 截图 / 快照 | 是否需发布前/后截图 | 是 → 用 `fetch-snapshot` |
| 10 | 发布路径 | 生产 basePath 是否需要别名 | 默认 `/mini-app/{appid}` |

### 7.2 AI 设计阶段的标准输出物

按以下顺序产出，每件产物均落到 `mini-app-skeleton` 工作副本的对应目录。

#### 阶段 A：项目骨架规划

- [ ] 确定 `appId`、确认数据库命名（按 `{appId}.db`）
- [ ] 确认 `package.json` 依赖是否需要新增（如 echarts、xlsx 等）
- [ ] 确认 `tsconfig.json` 路径别名（默认 `@/` → `next-app/`）

#### 阶段 B：数据库 Schema 设计

按 3.2 命名规则：

```bash
# 例：
db/DDL/v1.create-table-users.sql
db/DDL/v2.create-table-departments.sql
db/DDL/v3.add-index-on-user-name.sql
```

DDL 必须：

- 使用 `CREATE TABLE IF NOT EXISTS` 等幂等语法
- 多语句支持，每行一条
- 含必要索引、外键
- 不可逆：提交后只新增版本，不修改历史

#### 阶段 C：业务 SQL 定义

按 3.3 格式，按业务域拆文件：

```bash
# 例：
db/sql/users.sql.json
db/sql/departments.sql.json
db/sql/checklist.sql.json
```

每个文件结构：

```json
{
  "getPage": "SELECT ... WHERE user_name LIKE ? LIMIT ? OFFSET ?",
  "insert":  "INSERT INTO ... VALUES (?, ?, ?)",
  "update":  "UPDATE ... SET ... WHERE id = ?",
  "delete":  "DELETE FROM ... WHERE id = ?"
}
```

约定：

- key 用驼峰命名（getPage / getById / insertXxx）
- 所有可变部分必须 `?` 占位，禁止字符串拼接
- 一个 key 一条 SQL，不支持多语句

#### 阶段 D：前端页面与组件开发

按 2.1 Monorepo 结构，落点：

```
next-app/app/                     # 页面（App Router）
  layout.tsx                      # 根布局（含登录态、SSO Token 注入）
  page.tsx                        # 首页（按业务调整）
  login/                          # 登录页（如需独立页面）
  checklist/                      # 业务页（按业务划分）
    page.tsx
    detail/[id]/page.tsx
next-app/components/              # 业务组件
  ChecklistTable.tsx
  UserSearch.tsx
next-app/lib/types/               # 类型
  checklist.ts
  user.ts
next-app/lib/const/               # 常量
  checklist-status.ts
next-app/lib/store/               # Zustand store
  useChecklistStore.ts
```

**强制约束**（不遵守则报错）：

- 所有 `public/` 资源引用必须用 `$static()`：`$static('/assets/logo.png')`
- 路径导入必须用 `@/` 别名
- 状态管理用 Zustand（客户端）+ React Query（服务端）
- UI 组件优先 Ant Design 6.3
- 不修改 `lib/client-fetch/`、`lib/service/`、`util/public.ts`、`next.config.ts`

#### 阶段 E：请求层集成

```ts
// 单条查询
import { clientDBFetch } from '@/lib/client-fetch/client-db-fetch';

const data = await clientDBFetch({
  sqlFile: 'checklist.sql.json',
  sqlKey: 'getPage',
  sqlParams: [`%${keyword}%`, pageSize, offset],
});

// 批量查询（事务性场景）
import { clientDBBatchFetch } from '@/lib/client-fetch/client-db-batch-fetch';

const result = await clientDBBatchFetch([
  { sqlFile: 'checklist.sql.json', sqlKey: 'insert', sqlParams: [a, b, c] },
  { sqlFile: 'checklist.sql.json', sqlKey: 'insert', sqlParams: [d, e, f] },
]);

// 机构前置库查询
import { clientPreDBFetch } from '@/lib/client-fetch/client-pre-db-fetch';
const orgs = await clientPreDBFetch({ sqlId: 'org.list', params: [...] });
```

**禁止**：在代码中直接写 SQL 字符串；调用 `fetch('/gateway/...')` 直连；硬编码 basePath。

#### 阶段 F：构建与预览

```bash
# 1. 提交工作区（必须干净）
git add -A && git commit -m "feat: 初始化应用骨架"

# 2. 执行构建脚本（根目录）
bun run build:dev

# 3. 预览 URL
# /mini-app-dev/{appId}/{commithash}
```

#### 阶段 G：发布

```bash
# 通过管理面板触发
curl -N "https://.../mini-app/config/publish/exec?appId={appId}&commitHash={commithash}"
# SSE 流式返回：connected → step/log → ping(30s) → end
```

发布过程中由 BFF 自动执行：

- 文件锁（mkdir）→ 心跳守护（30s）→ 全局队列（concurrency=1）
- Step1 check → Step2 install → Step3 build → Step4 deploy（原子替换） → Step5 cleanup

### 7.3 AI 自检清单（开发完成前必跑）

- [ ] `basePath` 是否通过 `static-config.ts` 自动计算（无硬编码）
- [ ] 所有静态资源是否用 `$static()`
- [ ] 所有 SQL 是否走 `db/sql/*.sql.json`，无字符串拼接
- [ ] 所有 DDL 是否按 `v{n}.{description}.sql` 命名
- [ ] 工作区是否干净（`git status` 无未提交）
- [ ] 是否触发了 `lib/client-fetch/`、`lib/service/`、`util/public.ts`、`next.config.ts`
- [ ] 是否新增了需要的依赖到 `package.json`
- [ ] 是否配置了必要的鉴权/权限字段
- [ ] 是否测试了 `build-dev.sh` 构建成功
- [ ] 是否拿到了可访问的预览 URL（带 commit hash）

### 7.4 典型轻应用骨架示例（最小可运行）

> 假设需求：「做一个轻应用，列出审计检查项并支持按部门筛选」

#### 7.4.1 元数据

```
appId: audit-checklist
name: 审计检查项清单
NAS 路径: 由 Gateway /agent-platform/miniApp/getNasMappingPath?appId=audit-checklist&env=prd 返回
basePath (生产): /mini-app/audit-checklist
basePath (dev):   /mini-app-dev/audit-checklist/{commithash}
```

#### 7.4.2 数据库

```bash
db/DDL/v1.create-table-checklist.sql
db/DDL/v2.create-table-departments.sql
```

```sql
-- v1.create-table-checklist.sql
CREATE TABLE IF NOT EXISTS checklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  department_id INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_checklist_dept ON checklist(department_id);

-- v2.create-table-departments.sql
CREATE TABLE IF NOT EXISTS departments (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);
```

#### 7.4.3 SQL 定义

```json
// db/sql/checklist.sql.json
{
  "getPage": "SELECT id, title, status, created_at FROM checklist WHERE department_id = ? ORDER BY id DESC LIMIT ? OFFSET ?",
  "getById": "SELECT * FROM checklist WHERE id = ?",
  "insert":  "INSERT INTO checklist (title, description, department_id) VALUES (?, ?, ?)",
  "update":  "UPDATE checklist SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
  "delete":  "DELETE FROM checklist WHERE id = ?"
}

// db/sql/departments.sql.json
{
  "listAll": "SELECT id, name FROM departments ORDER BY id"
}
```

#### 7.4.4 前端页面

```tsx
// next-app/app/page.tsx
'use client';
import { useState, useEffect } from 'react';
import { Table, Select, Input } from 'antd';
import { clientDBFetch } from '@/lib/client-fetch/client-db-fetch';

export default function Home() {
  const [data, setData] = useState([]);
  const [depts, setDepts] = useState([]);
  const [deptId, setDeptId] = useState<number>();
  const [keyword, setKeyword] = useState('');

  useEffect(() => {
    clientDBFetch({ sqlFile: 'departments.sql.json', sqlKey: 'listAll', sqlParams: [] })
      .then((res) => setDepts(res.data.result));
  }, []);

  const load = async () => {
    const res = await clientDBFetch({
      sqlFile: 'checklist.sql.json',
      sqlKey: 'getPage',
      sqlParams: [deptId || 0, 20, 0],
    });
    setData(res.data.result);
  };

  useEffect(() => { load(); }, [deptId]);

  return (
    <div>
      <Select options={depts.map(d => ({ label: d.name, value: d.id }))} onChange={setDeptId} />
      <Input.Search onSearch={(v) => setKeyword(v)} />
      <Table dataSource={data} columns={[
        { title: 'ID', dataIndex: 'id' },
        { title: '标题', dataIndex: 'title' },
        { title: '状态', dataIndex: 'status' },
      ]} />
    </div>
  );
}
```

#### 7.4.5 静态资源引用（必须用 $static）

```tsx
// ✓ 正确
<img src={$static('/assets/logo.svg')} alt="logo" />

// × 错误
<img src="/assets/logo.svg" alt="logo" />
```

#### 7.4.6 构建与发布

```bash
git add -A
git commit -m "feat: 初始化审计检查项清单"
# 记录 commit hash: e.g. abc1234...
bun run build:dev

# 管理面板触发发布，传入 appId=audit-checklist&commitHash=abc1234
```

### 7.5 AI 调用本规范的「前置必读」与「避坑清单」

**前置必读**（接到任何任务前 5 分钟读完）：

1. §0 TL;DR
2. §1.6 关键设计决策（5 条）
3. §2.10 内置模块约定（不要碰的文件清单）
4. §3.2.3 DDL 规范 + §3.3 预定义 SQL 规范
5. §6.1 Agent 可操作范围

**避坑清单**（写代码时必须自检）：

| 坑 | 表现 | 解法 |
|----|------|------|
| ❌ 直写 SQL | 在 `.tsx` 中拼 `` `SELECT * FROM ...` `` | 必须移到 `db/sql/*.sql.json` |
| ❌ 硬编码 basePath | `<img src="/assets/x.png">` | 用 `$static('/assets/x.png')` |
| ❌ 直接 fetch | `fetch('/gateway/...')` | 用 `clientFetchGateway` |
| ❌ 跳过 LRU 缓存 | 自己写 SQL 文件加载逻辑 | 走 BFF 内置 `loadSqlDefinition` |
| ❌ 改内置模块 | 修改 `lib/client-fetch/*.ts` | 视为禁止，写扩展 |
| ❌ DDL 重复版本号 | `v2` 出现两次 | 严格递增 |
| ❌ 修改已发布 DDL | 改了 `v1.create-table-xxx.sql` | 只能新增 `v2` |
| ❌ 不干净工作区构建 | `build-dev.sh` 报错 | `git add -A && git commit` |
| ❌ 没等 Step5 完成 | 看到 end 事件就立刻访问 | 等 SSE end: {code:200} 再访问 |
| ❌ 跳过权限检查 | 页面直接暴露所有功能 | 用 `useAuthStore.hasPermission()` |

---

## 附录 A：文件索引

### A.1 前端框架

| 文件 | 说明 |
|------|------|
| `mini-app/README.md` | 项目总览 |
| `mini-app/next-app/AGENTS.md` | 前端开发指南 |
| `mini-app/db/AGENTS.md` | 数据库管理指南 |
| `mini-app/build-dev.sh` | 开发构建脚本 |
| `mini-app/package.json` | Monorepo 根配置 |
| `mini-app/next-app/next.config.ts` | Next.js 配置 |
| `mini-app/next-app/lib/service/static-config.ts` | 静态配置 |
| `mini-app/next-app/lib/service/dynamic-config.ts` | 动态配置 |
| `mini-app/next-app/lib/client-fetch/client-fetch.ts` | 基础请求方法 |
| `mini-app/next-app/lib/client-fetch/client-db-fetch.ts` | 数据库查询封装 |
| `mini-app/next-app/lib/client-fetch/client-db-batch-fetch.ts` | 数据库批量查询封装 |
| `mini-app/next-app/lib/client-fetch/client-pre-db-fetch.ts` | 前置库查询封装 |
| `mini-app/next-app/util/public.ts` | `$static` 函数封装 |
| `mini-app/db/run-ddl.py` | DDL 执行脚本 |

### A.2 工程控制（BFF 端）

| 文件 | 说明 |
|------|------|
| `agent-bff/app/bff/mini-app/db/route.ts` | 单条 SQL 查询接口 |
| `agent-bff/app/bff/mini-app/db-batch/route.ts` | 批量 SQL 查询接口 |
| `agent-bff/app/bff/mini-app/config/publish/exec/route.ts` | 发布执行接口 |
| `agent-bff/app/bff/mini-app/config/publish/query/route.ts` | 发布状态查询接口 |
| `agent-bff/app/bff/mini-app/config/publish/lock-utils.ts` | 文件锁工具 |
| `agent-bff/app/bff/mini-app/config/publish/heartbeat-guard.ts` | 心跳守护 |
| `agent-bff/app/bff/mini-app/config/publish/steps/step-1-check.sh` | 检查步骤 |
| `agent-bff/app/bff/mini-app/config/publish/steps/step-2-install.sh` | 安装步骤 |
| `agent-bff/app/bff/mini-app/config/publish/steps/step-3-build.sh` | 构建步骤 |
| `agent-bff/app/bff/mini-app/config/publish/steps/step-4-deploy.sh` | 部署步骤 |
| `agent-bff/app/bff/mini-app/config/publish/steps/step-5-cleanup.sh` | 清理步骤 |
| `agent-bff/app/bff/mini-app/config/fetch-snapshot/route.ts` | 截图接口 |
| `agent-bff/app/bff/mini-app/config/route-list/route.ts` | 路由列表接口 |
| `agent-bff/app/bff/mini-app/lib/db.ts` | SQL 定义加载 |
| `agent-bff/app/bff/mini-app/lib/mini-app-root-resolve.ts` | NAS 路径解析 |

---

## 附录 B：术语速查

| 术语 | 含义 |
|------|------|
| 轻应用 | 基于本规范构建的静态 Web 应用，由 Agent 驱动开发 |
| BFF | Backend For Frontend，本规范中为 Next.js API Routes 服务（`agent-bff`） |
| Gateway | 企业内部微服务网关，提供 SQL 执行、NAS 路径解析等基础能力 |
| NAS | Network Attached Storage，挂载的远程文件系统 |
| LRU | Least Recently Used，本规范中用于缓存 NAS 路径/SQL 定义 |
| mkdir 原子操作 | 利用文件系统 `mkdir` 的原子性实现分布式锁 |
| commitHash | Git commit hash，本规范中作为版本主键贯穿全流程 |
| basePath | Next.js 的 base 路径，本规范中随环境/应用动态计算 |
| $static | 自定义函数，自动拼接 basePath 生成静态资源 URL |
| sqlKey | 预定义 SQL 的 key，前端通过 key 引用 SQL |
| sqlFile | 预定义 SQL 文件名（如 `users.sql.json`） |
| sqlParams | SQL 参数数组，按占位符顺序填入 |
| SQL 预定义 | 所有业务 SQL 必须以 JSON 文件形式存储，禁止代码拼接 |
| DDL | Data Definition Language，本规范中指 SQLite 表结构变更脚本 |
| DDL 不可逆 | 已提交的 DDL 脚本不允许二次修改，只能新增版本 |
| 三级并发控制 | mkdir 文件锁 + 心跳 + 全局队列 |
| SSE | Server-Sent Events，本规范中用于流式发布进度 |

---

## 附录 C：变更记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-09-11 | v1.0 | 首次整理，基于公司内网技术规范拍照 IMG_4948~IMG_4985 |
| 2026-09-11 | v1.1 | 对照原图与 OCR 全文复核：修正 `exeSql/exeBatchSql`、`executePreDBSql`、`out-prd__prev/__next`、`.publish_lock`、`.DDLFILES`、`getSSOToken/getLoginUrl`、`build:dev`、`distDir: out`、BFF 文件路径等；重写 §1.3 架构图与 §2.1 Monorepo 树；补充 §4.6.8；校正 §2.2 技术栈版本表 |
| 2026-09-11 | v1.2 | 二轮原图复核：补全 §1.2 角色表「技术实现」列（共 7 角色）、§2.3.2 代码 `${APP_GIT_VER}`、§4.5.1 SSE 事件 `ping`/`end` 数据纠正、§1.6 决策 2 补 `sqlFile`、§6 标题按原文校准 |
| 2026-09-11 | v1.3 | 三轮复核修正：① §1.2 角色表补回「数据库」角色（共 8 角色）；② §4.5.1 SSE 事件 `ping` 数据改回 `{code,msg}`、`end` 改回 `{}`（此前一轮纠正反了）；③ §2.2 技术栈版本错位校正（CSS 方案 = 5/5.90，状态管理/测试框架无版本号）；④ §4.5.4 截图返回码 `IOBS`（OCR 噪声）改回 `1005` |
| 2026-09-11 | v1.4 | 终核（逐张对照 38 张 OCR 原文）：§1~6 章 + 附录 A 全部技术内容与照片一致；修正 §0 TL;DR 角色列表漏「数据库」（补为 8 类）。仅保留 1 处存疑点（Gateway `exeSql` 拼写，待李哥核对原图） |

---

_本文档根据拍照的 38 张公司内网技术规范整理，原始照片位于 `/Users/aatrox/Desktop/appmd/readme/`。后续如有规范更新，请拍照补充并同步修订本文件。_
