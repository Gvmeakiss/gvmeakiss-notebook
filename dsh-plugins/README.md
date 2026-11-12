# DSH 插件配置快照

> 记录**这台机器的 DeepSeek Harness（dsh）profile 装了哪些插件、怎么配置**，让它在别的机器上能复现，
> 也让"我装过什么"不再只存在于 `%USERPROFILE%\.dsh` 里。

**边界**：这里存的是**配置与清单**，不是插件源码。三个插件都是第三方发布的 npm 包（MIT），
仓库不 vendor 它们的代码；`node_modules` 属于构建产物，不入库。配置文件里也没有凭据。

## 当前安装的插件

| 插件 | 版本 | 作者 / 上游 | 状态 | 作用 |
|---|---|---|---|---|
| [dsh-ops](https://github.com/T-Auto/dsh-ops) | 0.5.4 | T-Auto | ✅ 启用 | 原生文件与 PTC 工具（Windows x64 / Linux x64 / macOS），含可选 Bash 载荷与 PowerShell 集成。本会话里的 `ops_*` 工具就来自它 |
| [dsh-claude-style](https://github.com/Nwflower/dsh-claude-style) | 0.13.3 | Nwflower | ✅ 启用 | Web GUI 的 Claude Code 桌面主题：品牌、配色、首页布局、吉祥物等视觉与交互改造 |
| [dsh-purge-archived](https://github.com/trimine/dsh-purge-archived) | 1.0.1 | trimine | ✅ 启用 | 彻底删除已归档会话：会话日志、投影缓存、归档标记、工作区归属，并提供批量清理页 |
| @deepseek-ai/dsh-subagent-codex | 0.2.1-rc.3 | DeepSeek 官方 | ⛔ 已装但禁用 | 声明依赖 `0.2.1-rc.3` 系模块，运行时是 `0.2.2-rc.1`，版本门控判定 `incompatible-version`，因此不加载。升级到匹配版本后会自动可用 |

加载顺序（`package.json` → `dsh.profile.bundles`，顺序即补丁层顺序）：

```
@deepseek-ai/dsh-base
@deepseek-ai/dsh-web-app
@deepseek-ai/dsh-experimental-terminal-bundle
@deepseek-ai/dsh-experimental-session-titles-bundle
@deepseek-ai/dsh-experimental-plugin-market-bundle
dsh-purge-archived
dsh-ops
@deepseek-ai/dsh-experimental-auto-review
dsh-claude-style
```

## 快照里有什么

| 文件 | 作用 | 改动风险 |
|---|---|---|
| `profile/package.json` | 依赖版本范围 + `dsh.profile.bundles`（装什么、按什么顺序加载） | 高：决定 profile 的插件集合 |
| `profile/cordis.yml` | profile 根，正常是空数组，真正的配置在补丁层 | 低 |
| `profile/cordis.patch.yml` | **你的覆盖**：默认模型（`deepseek-flash`）、思考强度、UI 偏好、权限预设、插件市场索引、`dsh-claude-style` 主题参数、模型上下文窗口定义 | 中：改了会直接改变交互行为 |
| `profile/pnpm-lock.yaml` | 解析后的精确版本，保证换机器装出同一套 | 低（自动生成） |

## 复现（换一台机器）

1. 装好 dsh 桌面版并至少运行一次，让 `%USERPROFILE%\.dsh\profiles\desktop` 生成；
2. 把本目录 `profile/` 下的四个文件覆盖进去（覆盖前先备份原 profile）；
3. 安装依赖：在该 profile 目录执行 `pnpm install`（或用 GUI 的插件管理逐个安装下面三项）；
   - 只想要功能、不需要主题：`pnpm add dsh-ops dsh-purge-archived`
   - 主题：`pnpm add dsh-claude-style`
4. 重启 dsh。

> 插件是第三方包，安装即从 npm 拉取并执行其代码；版本以 `package.json` 的记录为准，
> 升级前先看上游仓库的变更说明。

## 核对（本机现状 vs 快照）

```powershell
pwsh -File scripts/check-profile.ps1
```

只读比对：依赖名与版本范围、bundle 顺序、三个配置文件哈希、以及每个非官方 bundle 在
`node_modules` 里的实际版本。一致退出 0；有漂移退出 1 并逐条列出；profile 或快照缺失退出 2。

## 更新（改了插件之后）

```powershell
pwsh -File scripts/export-profile.ps1 -WhatIf   # 先看会改哪些
pwsh -File scripts/export-profile.ps1           # 真写，逐文件 SHA256 校验
git diff -- dsh-plugins/profile                 # 只提交有意为之的变化
```

导出时**不复制** `node_modules`（构建产物），也不采集任何凭据。若未来 dsh 版本开始把密钥写进
`cordis.patch.yml`，`git diff` 会看见 —— 提交前务必过一眼。

## 维护约定

- 装/删/升级插件后，跑一次 `export-profile.ps1` 并提交快照，否则 `check-profile.ps1` 会报漂移。
- 版本以 `package.json` 的版本范围为准；`pnpm-lock.yaml` 只用于复现，不要手改。
- 配置里的个人偏好（模型、权限预设、主题参数）属于本机事实，换机器按需保留或调整。

---

<p align="right"><sub><a href="../README.md">← 笔记本目录</a> · <a href="./profile/package.json">package.json</a> · <a href="./scripts/check-profile.ps1">核对脚本</a></sub></p>
