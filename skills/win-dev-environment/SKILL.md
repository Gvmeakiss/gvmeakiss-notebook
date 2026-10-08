---
name: win-dev-environment
description: 在 Windows 上审计、修复并验证开发环境（非管理员账户）。当出现"审阅一下计算机环境""安装编程语言/配置环境""某个语言明明装了却提示找不到""命令行工具未找到""配置国内镜像源""Windows 上构建失败但 Mac/Linux 正常"等诉求时使用。核心价值是识别 Windows 专属的"假缺失"陷阱——工具已安装却被 Store 存根、PATH 陈旧或区域编码劫持，报错信息与真实原因完全不符。
agent_created: true
---

# Windows 开发环境：审计 · 修复 · 验证

## 适用场景

用户想**在 Windows 上把开发环境弄好**，而不是排查业务代码。典型触发：

- "审阅一下计算机环境，安装对应编程语言及配置环境"
- "python/node 明明装了，一敲命令却提示要从应用商店安装"
- "某个命令 not recognized / 不是内部或外部命令"
- "帮我配一下国内镜像源"
- "这段代码在 Mac 上能编译，Windows 上就失败"
- 接手一台新机器/新账户，准备开始开发

## 核心判断：区分"真缺失"与"假缺失"

**这是本 Skill 最重要的方法论。** Windows 上大量"缺少工具"的报告是假的，真实原因只有四类：

| 症状 | 真实原因 | 为什么会误判 |
|---|---|---|
| `python` 提示"从 Microsoft Store 安装" | `WindowsApps` 里的 **App Execution Alias 存根**（0 字节重解析点）优先级高于任何 PATH 条目 | 用户以为 Python 没装，实际已装好 |
| 所有 scoop 装的命令都 `not recognized` | `%USERPROFILE%\scoop\shims` **不在 PATH**，或当前进程环境陈旧 | 以为整套工具链都缺失 |
| 命令时有时无 | **GUI 父进程的 PATH 比配置更早**，子进程继承陈旧环境 | 反复重装，问题照旧 |
| 工具装了但模块找不到 | 包管理器把脚本装进 `persist\` 等**未加入 PATH 的目录** | 以为安装失败 |

**因此第一条纪律：任何"缺失"结论都必须先验证 PATH 与存根，再谈安装。**

## 工作流程

### 第一步：审计（只读，绝不修改）

```powershell
pwsh -File scripts/audit-env.ps1            # 人读报告
pwsh -File scripts/audit-env.ps1 -Json      # 机器可读
```

报告覆盖：OS/硬件（**含 `IsWindows11OrLater`**）、权限、工具链版本、**PATH 重复与失效条目**、用户环境变量、包管理器缓存、磁盘占用、**镜像可达性**、**DNS 解析**。

`IsWindows11OrLater` 单独列出是有原因的：大量 GUI 自动化 / UIA 工具链只支持 Windows 11（build 22000+）。**先确认平台，再决定要不要装**，能避免整条技术路线走死。

### 第二步：修复已知陷阱

```powershell
pwsh -File scripts/fix-env.ps1 -WhatIf      # 先干跑，看清将做什么
pwsh -File scripts/fix-env.ps1              # 应用
```

覆盖 7 类问题：scoop shims 入 PATH、移除 Store 存根并补建真实 shim、失效/重复 PATH 条目、标准工具目录、**git 凭据助手污染**、**Rust GNU 的 dlltool 依赖**、广播环境变更。幂等，可反复运行。

### 第三步：安装工具链

```powershell
pwsh -File scripts/setup-langs.ps1
pwsh -File scripts/setup-langs.ps1 -Packages python,node,go
```

**关键决策：非管理员账户不能用 MSI。** 机器级 MSI 需要提权，会静默失败或留下半成品。因此：

- 一律走 **Scoop 用户级安装**（无需 UAC）
- **Rust 用 rustup 装 GNU 目标，不用 scoop 的 `rust`**（后者是 MSI）；GNU 目标复用已装的 MinGW binutils，**完全避开需要管理员的 Visual Studio Build Tools**

### 第四步：验证（真实编译，不是看版本号）

```powershell
pwsh -File scripts/verify-env.ps1
pwsh -File scripts/verify-env.ps1 -Languages python,go,rust
```

**版本号不是证据。** 一个工具链可以正常打印 `--version` 却完全不可用（PATH 错、目标平台错、缺链接器、镜像不通）。本步骤对每种语言做**真实构建 + 运行**，并在需要时**实际拉取一个依赖**以验证镜像。

失败判定区分「工具链缺陷」与「可选配置」——例如未配置 SSH 密钥只报 `INFO`，不让整体失败。

## 必须留意的 Windows 专属陷阱

这些是实战中反复出现的，每一条都产生与实际原因不符的报错：

### 1. Python：Store 存根劫持 + 区域编码

- **存根劫持**：删掉 `WindowsApps\python.exe` / `python3.exe` 后再补建真实 shim。注意 scoop 的 python 清单**可能只建 `python3` 而不建 `python`**。
- **区域编码**：Windows 上 Python 默认用**区域代码页（中文系统为 GBK）**读文件，于是 `Path.read_text()` 读取含中文的 UTF-8 文件会抛 `UnicodeDecodeError`。**代码在 Mac/Linux 上正常，在 Windows 上失败。**
  - 正确修法：代码里显式 `encoding='utf-8'`（跨平台一致，不依赖环境）
  - 辅助手段：`PYTHONUTF8=1`（全局默认 UTF-8）
  - **不要把环境变量当唯一修法** —— CI 和别人的机器不会设它

### 2. Rust：GNU 目标需要 dlltool

GNU 目标链接 proc-macro 时调用 `dlltool`。缺失时报错发生在**依赖构建深处**，信息极具误导性：

```
error calling dlltool 'dlltool.exe': program not found
```

看起来像 crate 有问题，实际是 binutils 不在 PATH。**因此验证脚本特意用 `rand`（会引入需要链接的依赖）而不是空 crate。**

### 3. Git：`credential-manager configure` 会污染配置

该命令会往**系统级** `etc/gitconfig` 写入空值 `credential.helper =`，并在全局配置追加**转义错误的绝对路径**。空值会让 git **忽略真正的 helper** 并回退到终端询问——表现像"凭据坏了"。

```powershell
git config --system --unset-all credential.helper
git config --global --unset-all credential.helper   # 然后只保留一条正确的
```

### 4. 认证：浏览器登录态会劫持 CLI 授权

HTTPS + Git Credential Manager 会打开浏览器 OAuth 页。**若浏览器已登录另一个账号，GitHub 会直接用它批准请求**，于是永远拿不到目标账号的令牌。多账号机器上尤其隐蔽。

可靠解法（按推荐度）：
1. **`gh auth login` 设备码方式** —— 显式输入码，不复用浏览器登录态；之后 `gh auth setup-git` 让 token 直接供 git 使用
2. **SSH 密钥** —— 完全不走浏览器；注意 `github.com:22` 可能被网络阻断，改用官方的 `ssh.github.com:443`

### 5. 端口 22 被封

国内网络常见：TCP 能连通但握手被切断（`kex_exchange_identification: Connection closed by remote host`）。改用 `ssh.github.com:443`，并**用 GitHub 官方公布的指纹校验主机密钥**。

### 6. PowerShell 脚本自身的坑（写脚本时）

- **`$PSCmdlet` 只在带 `[CmdletBinding()]` 的函数内存在。** 普通函数里它是 `$null`，调用 `.ShouldProcess()` 会抛错；在 `$ErrorActionPreference='Continue'` 下**静默失败、函数直接中断**，极难排查。解法：脚本级 `$Cmdlet = $PSCmdlet` 后统一使用。
- **`[void](SomeFunction)` 会丢弃该函数的全部输出**，包括你写在里面的提示信息。
- 哈希表的裸键名不能含 `+` 等运算符字符：`'g++'` 必须加引号。
- 脚本里**必须从注册表重建 PATH**（Machine + User 拼接），否则 GUI 父进程带来的陈旧环境会让已安装工具报告"缺失"。

## 镜像源（中国大陆网络）

| 生态 | 配置方式 | 地址 |
|---|---|---|
| pip | `pip config set global.index-url` | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| npm | `npm config set registry` | `https://registry.npmmirror.com` |
| Go | `go env -w GOPROXY` | `https://goproxy.cn,direct` |
| Cargo | `~/.cargo/config.toml` | `sparse+https://rsproxy.cn/index/` |
| rustup | `RUSTUP_DIST_SERVER` | `https://rsproxy.cn` |
| NuGet | `%APPDATA%\NuGet\NuGet.Config` | nuget.org 主 + 华为云备 |

镜像只验证"可达"是不够的 —— 验证脚本会**实际安装一个包/拉取一个模块**来证明链路真的通。

## 交付前检查清单

- [ ] 审计报告已生成，`IsWindows11OrLater` 已确认
- [ ] 所有"缺失"结论都排除了 PATH 陈旧与 Store 存根
- [ ] 修复脚本以 `-WhatIf` 干跑并确认无意外删除
- [ ] 每种语言都做了**真实编译+运行**，而非只看版本号
- [ ] 至少一条镜像链路通过**实际拉取依赖**验证
- [ ] 检查清单里没有把用户真实凭据、邮箱、主机名写进仓库
- [ ] 明确告知：**已打开的终端需重开**才生效

## 边界

- **仅 Windows**；macOS/Linux 的环境问题不适用本方法论
- 脚本**只做用户级改动**，绝不提权、不写机器级注册表
- 非管理员账户**无法**安装 MSVC 工具链、系统级软件、`%ProgramFiles%` 内容
- 管理员权限窗口无法被 GUI 自动化操作（Windows 既定边界）
