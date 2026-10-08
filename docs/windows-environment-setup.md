# Windows 开发环境 · 配置记录

一台 Windows 10 机器的开发环境与常用软件，从**零**到**可用**的完整过程，以及过程中解决的每一个问题。
这不是一份教程，而是一份**实测记录** —— 每个结论都来自在这台机器上真实跑出来的结果。

- **仓库**：[Gvmeakiss/gvmeakiss-notebook](https://github.com/Gvmeakiss/gvmeakiss-notebook)
- **方法论已固化为 2 个 Skill**：
  - [`skills/win-dev-environment`](https://github.com/Gvmeakiss/gvmeakiss-notebook/tree/main/skills/win-dev-environment) —— 开发环境审计/修复/验证
  - [`skills/win-portable-apps`](https://github.com/Gvmeakiss/gvmeakiss-notebook/tree/main/skills/win-portable-apps) —— 便携软件安装与盘点
- **环境**：Windows 10 Pro 22H2 (build 19045) · **非管理员账户** · PowerShell 7.6.6

---

## 快速索引

| 我想… | 看这里 |
|---|---|
| 知道装了什么、什么版本 | [§2 最终环境](#2-最终环境) |
| 复现整套配置 | [§7 可复现命令](#7-可复现命令) |
| 看踩过哪些坑 | [§4 问题总表](#4-问题总表按危害排序) |
| 了解 Windows 专属陷阱 | [§5 Windows 专属陷阱](#5-windows-专属陷阱) |
| 继续用这套方法论 | [§6 已固化为 Skill](#6-已固化为-skill) |
| 还有什么没做完 | [§8 未完成事项](#8-未完成事项) |

---

## 1. 起点与终点

### 起点

| 项目 | 状态 |
|---|---|
| 编程语言环境 | **一个都没有**（无 Python / Node / Java / Go / Rust / C / C++ / .NET） |
| 包管理器 | **无 winget / choco**；有 Scoop 但**未生效**（shims 不在 PATH） |
| 账户权限 | **非管理员** —— 不能提权、不能装机器级 MSI |
| 网络 | 直连可用；但 `nodejs.org`、`static.rust-lang.org` 存在 **DNS 污染**；`github.com:22` **被阻断** |
| 已有工具 | Git 2.56、7-Zip 26.04、Scoop v0.6.0（均处于"装了但用不了"状态） |

### 终点

**8 种语言工具链全部可用**，且每一条都经过**真实编译运行**验证（不是只看版本号）：

```
Python 3.14.8    Node.js 26.11.1   Go 1.27.2       Rust 1.99.0
Java 21.0.12.1   .NET 10.0.401     GCC/G++ 16.2.0  CMake 4.4.4
Git 2.56.0       GDB 17.2          GNU Make 4.4.1  gh 2.102.0
```

外加 6 个国内镜像源、修复 7 类环境缺陷、为仓库建立 CI、合并搁置 3 周的 PR。
磁盘净变化约 +5 GB，C 盘可用 840 GB。

**另有 8 个便携软件**（文本 / Markdown / 图片查看 ×3 / 音视频 ×2 / 网络存储），
全部免安装、免提权，装在 `~\Apps`，删文件夹即卸载。见 [§6.2](#62-skills-win-portable-apps--便携软件安装)。

---

## 2. 最终环境

### 工具链

| 语言 / 工具 | 版本 | 安装位置 |
|---|---|---|
| Python / pip | 3.14.8 / 26.2.1 | `~\scoop\apps\python\current` |
| Node.js / npm | 26.11.1 / 11.20.0 | `~\scoop\apps\nodejs\current` |
| Go | 1.27.2 | `~\scoop\apps\go\current` |
| Rust / Cargo | 1.99.0 | `~\.rustup` / `~\.cargo` |
| Java (Temurin JDK) | 21.0.12.1 LTS | `~\scoop\apps\temurin21-jdk\current` |
| GCC / G++ | 16.2.0 (MinGW-w64, UCRT, POSIX, SEH) | `~\scoop\apps\mingw\current\bin` |
| GDB / GNU Make | 17.2 / 4.4.1 | 同上 |
| CMake | 4.4.4 | `~\scoop\apps\cmake\current` |
| .NET SDK | 10.0.401 | `~\scoop\apps\dotnet-sdk\current` |
| Git / gh / 7-Zip | 2.56.0 / 2.102.0 / 26.04 | `~\scoop\apps\...` |

> **Rust 的目标平台是 `x86_64-pc-windows-gnu`**（不是 MSVC）。
> 原因：MSVC 工具链的 MSI 安装需要管理员权限，非管理员账户无法使用；
> GNU 目标直接复用已装的 MinGW-w64，**完全免提权**。

### 镜像源

| 生态 | 配置位置 | 地址 |
|---|---|---|
| pip | `%APPDATA%\pip\pip.ini` | 清华 `pypi.tuna.tsinghua.edu.cn` |
| npm | npm 用户配置 | `registry.npmmirror.com` |
| Go | `go env -w` | `goproxy.cn` |
| Cargo | `~/.cargo/config.toml` | `rsproxy.cn` |
| rustup | `RUSTUP_DIST_SERVER` | `rsproxy.cn` |
| NuGet | `%APPDATA%\NuGet\NuGet.Config` | nuget.org 主 + 华为云备 |

### 关键环境变量

```
JAVA_HOME          = ...\scoop\apps\temurin21-jdk\current
DOTNET_ROOT        = ...\scoop\apps\dotnet-sdk\current
GOPATH / GOPROXY   = C:\Users\<你>\go  /  https://goproxy.cn,direct
RUSTUP_DIST_SERVER = https://rsproxy.cn
NPM_CONFIG_REGISTRY= https://registry.npmmirror.com
PIP_INDEX_URL      = https://pypi.tuna.tsinghua.edu.cn/simple
PYTHONUTF8         = 1
```

---

## 3. 全过程概览

| 阶段 | 内容 | 结果 |
|---|---|---|
| 审阅 | 盘点 OS、硬件、权限、已装工具、网络、DNS | 发现语言环境全空 + 三类"假缺失" |
| 修复 | PATH、Store 存根、凭据链、失效条目 | 7 类缺陷修复 |
| 安装 | Scoop 用户级安装 8 种语言 + 配镜像 | 全部成功，零 UAC 提权 |
| 验证 | 每种语言**真实编译运行** + 拉取依赖 | 33 项检查通过 |
| 仓库 | 审计 + CI + 合并 PR + 新增 Skill 项目 | 见下 |

---

## 4. 问题总表（按危害排序）

| # | 问题 | 危害 | 修法 |
|---|---|---|---|
| 1 | **浏览器登录态劫持 CLI 的 OAuth 授权** | 永远拿不到正确账号的令牌，重试无效 | `gh auth login` 设备码 / SSH |
| 2 | **Python 被 Store 存根劫持** | 已装好却提示"去应用商店安装" | 删存根 + 补建 shim |
| 3 | **`Windows 区域编码`（GBK）破坏 UTF-8 读取** | 代码在 Mac/Linux 正常，Windows 失败 | 显式 `encoding='utf-8'` |
| 4 | **Scoop shims 不在 PATH** | 整套工具链显示"缺失" | 重写 PATH + 广播 |
| 5 | **GUI 父进程的陈旧 PATH** | 已装工具报告缺失，误导判断 | 脚本自行从注册表重建 PATH |
| 6 | **Rust GNU 缺 `dlltool`** | 报错发生在依赖深处，信息误导 | 装 MinGW binutils |
| 7 | **`git-credential-manager configure` 污染配置** | 空 `credential.helper` 让 git 忽略真 helper | 清除空值与坏路径 |
| 8 | **`github.com:22` 被阻断** | SSH 握手被切断 | 改用 `ssh.github.com:443` |
| 9 | **`ssh-keygen -N '""'` 把引号当口令** | 本地无法签名，但 GitHub 端已接受密钥 | `-N ""`（不加外层引号） |
| 10 | **Python 脚本权限位断言在 Windows 必然失败** | 测试红，但代码没问题 | 按平台条件断言 |
| 11 | **仓库搁置 3 周的 PR 与旧快照分支** | 越拖冲突越大，且有误删风险 | 只摘取目标目录重建 |
| 12 | **默认程序无法脚本设置** | 装机后无法自动改默认打开方式 | 接受限制，引导手动点一次 |
| 13 | **`-File` 模式不把 `A,B` 拆成数组** | 脚本收到 `"A,B"` 单元素，报"无匹配项" | 脚本自行按逗号拆分 |
| 14 | **便携软件不进"应用和功能"** | 只查系统列表会以为"什么都没装" | 目录扫描 + 多路并查 |

---

## 5. Windows 专属陷阱

这一节是本文最有价值的部分 —— 这些陷阱的共同特征是**报错信息与真实原因完全不符**。

### 5.1 「假缺失」四类

Windows 上"工具没装"的报告**大部分是假的**：

| 你看到的 | 真实原因 | 为什么误判 |
|---|---|---|
| `python` 提示去 Store 安装 | `WindowsApps\python.exe` 是 **0 字节重解析点**，优先级高于任何 PATH | 以为没装 |
| 所有 scoop 命令 `not recognized` | `~\scoop\shims` 不在 PATH | 以为整套缺失 |
| 重装无效、时好时坏 | **GUI 父进程环境比配置更早** | 反复重装 |
| 装好了但脚本找不到 | 包管理器装进 `persist\` 等未入 PATH 的目录 | 以为安装失败 |

**纪律**：任何"缺失"结论，必须**先排除 PATH 与存根**，再谈安装。

### 5.2 Python 的双重陷阱

**存根劫持**：`WindowsApps\python.exe` / `python3.exe` 是 0 字节重解析点。
注意 **scoop 的 python 清单可能只建 `python3` 而不建 `python`**。

**区域编码**：中文 Windows 上 Python 默认用 **GBK** 读文件：

```
UnicodeDecodeError: 'gbk' codec can't decode byte 0x9f in position 341
```

```python
path.read_text()                    # 错误：依赖平台默认编码
path.read_text(encoding='utf-8')    # 正确：跨平台一致
```

`PYTHONUTF8=1` 是辅助手段，**不能当唯一修法** —— CI 和别人的机器不会设它。

### 5.3 Rust：`dlltool` 缺失

GNU 目标链接 proc-macro 时调用 `dlltool`，缺失时报错发生在**依赖构建深处**：

```
error calling dlltool 'dlltool.exe': program not found
```

看起来像某个 crate 有问题，实际是 binutils 不在 PATH。

### 5.4 Git 凭据助手污染

`git-credential-manager configure` 会做两件有害的事：

1. 往**系统级** `etc/gitconfig` 写入**空值** `credential.helper =`
2. 往全局配置追加**转义错误的绝对路径**（路径里的空格被错误转义）

空值会让 git **忽略真正的 helper**，回退到终端询问 —— 表现像"凭据坏了"。

```powershell
git config --system --unset-all credential.helper
git config --global --unset-all credential.helper
git config --global credential.helper manager   # 只留一条正确的
```

> **注意区分**：`credential.https://github.com.helper=` 这种**带 URL 的**空值
> **不会**清空链（`gh auth setup-git` 会写它，是正常的）。只有**无 URL 的**
> `credential.helper=` 空值才有清空语义。

### 5.5 认证：浏览器登录态劫持

HTTPS + Git Credential Manager 会打开浏览器 OAuth 页。**若浏览器已登录另一个账号，
GitHub 会直接用它批准请求**，于是永远拿不到目标账号的令牌。多账号机器上极隐蔽。

追踪日志里的证据形式：

```
OpenBrowserInternal: Opening browser using shell-execute:
  https://github.com/login/oauth/authorize?...
username=<另一个账号>
```

**可靠解法（按推荐度）**：

1. **`gh auth login` 设备码方式** —— 显式输入 8 位码，**不复用浏览器登录态**；
   随后 `gh auth setup-git`，token 直接供 git 使用
2. **SSH 密钥** —— 完全不走浏览器

### 5.6 端口 22 被封锁

TCP 能连通，但握手被中途切断：

```
kex_exchange_identification: Connection closed by remote host
```

改用 GitHub 官方支持的 **`ssh.github.com:443`**，并**用官方指纹校验主机密钥**：

| 算法 | 官方指纹 |
|---|---|
| ED25519 | `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` |
| ECDSA | `SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM` |
| RSA | `SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s` |

来源：[GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)

### 5.7 SSH 密钥：`-N '""'` 的陷阱

```powershell
ssh-keygen -t ed25519 -f <path> -N '""'   # 错误：外层单引号让字面量两个引号成为口令
ssh-keygen -t ed25519 -f <path> -N ""     # 正确
```

后果很隐蔽 —— GitHub 那端**其实已经接受了**这个密钥：

```
debug1: Server accepts key: ... SHA256:xxxx      <- GitHub 接受了
debug2: we did not send a packet, disable method <- 但本地签名失败
```

**验证方式**：`ssh-keygen -y -f <key>` 应**直接输出公钥、不提示口令**。

### 5.8 PowerShell 脚本自身的坑

写这类脚本时最容易踩的四个：

```powershell
# 1) $PSCmdlet 只在 [CmdletBinding()] 函数内存在。普通函数里它是 $null，
#    调用 .ShouldProcess() 抛错；在 $ErrorActionPreference='Continue' 下静默中断，
#    表现为"函数一行都没执行，也没有任何报错"。
$Cmdlet = $PSCmdlet      # 脚本级捕获一次，之后统一用 $Cmdlet.ShouldProcess(...)

# 2) [void](SomeFunction) 会丢弃该函数的全部输出，包括写在里面的提示信息
# 3) 哈希表裸键名不能含运算符字符
$h = @{ 'g++' = @('--version') }    # g++ 必须加引号

# 4) 脚本必须自己从注册表重建 PATH，否则 GUI 父进程的陈旧环境会让已装工具报告缺失
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path','Machine'),
    [Environment]::GetEnvironmentVariable('Path','User')
) | Where-Object { $_ }) -join ';'
```

第 1 和第 4 条都**真实触发过**，且都**表现为错误的结论**而非报错。

### 5.9 默认程序无法脚本设置（UserChoice 保护）

装机时想"装完自动把图片默认程序改成新装的看图软件" —— **做不到，而且是设计使然。**

默认程序记在：

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<扩展名>\UserChoice
```

该键带**两重保护**：

1. **显式 `Deny SetValue` ACE**
2. **`Hash` 值**（ProgId + SID + 时间戳）

实测输出：

```
Access 规则:
  <用户>              Deny    SetValue      ← 显式拒绝
  <用户>              Allow   FullControl   ← Deny 仍然压过 Allow
  NT AUTHORITY\SYSTEM Allow   FullControl

键值:
  ProgId : AppX43hnxtbyyps62jhe9sqpdzxn1790zetc
  Hash   : Bjb6fycYDTA=

写入测试:
  Requested registry access is not allowed.
```

**`Deny` 优先于 `Allow FullControl`** —— 所以即便键的所有者是本人、即便是管理员也改不了。
这是**防静默劫持**的设计。

**能做与不能做**：

| 能做 | 不能做 |
|---|---|
| 备份关联注册表分支（`reg export`） | 修改默认程序 |
| 注册 ProgID，让程序**出现在"打开方式"列表** | 让它成为默认 |
| 精确报告哪些扩展名还需手动点 | 绕过 Hash |

**手动设置有效且持久**，实测 `.md` → Notepad++、`.png` → JPEGView、`.webp` → ImageGlass
均已成功关联并保持。只是一次点击无法由脚本代劳。

### 5.10 官方 COM API 存在，但在 Windows 10+ 上已失效

比"改不掉"更精确的结论 —— 值得单独记，避免重复试同一条死路。

微软**文档化的**接口 `IApplicationAssociationRegistration`（CLSID `591209c7-767b-42b2-9fba-44ee4615f2c7`）
确实存在，提供 `SetAppAsDefault` / `SetAppAsDefaultAll`。实测：

| 调用 | 结果 |
|---|---|
| `QueryAppIsDefault` | ✅ 正常工作，能**查询**真实默认程序 |
| `SetAppAsDefault` | ❌ 返回 **`0x80070002`**（`ERROR_FILE_NOT_FOUND`） |
| 实际效果 | **默认程序未被改动** |

**错误码本身也在误导** —— 它暗示"文件找不到"，真实原因是被策略禁止。

### 5.11 注册应用有两条路径，缺一不可

这是"注册了但用户还是找不到程序"的原因。两条路径作用不同：

| 注册位置 | 效果 | 漏了会怎样 |
|---|---|---|
| `HKCU\Software\Classes\Applications\<exe>` | 出现在右键**"打开方式"**列表 | 用户只能手动浏览到 exe |
| `HKCU\Software\<Vendor>\Capabilities`<br>+ `HKCU\Software\RegisteredApplications` | 出现在**设置 → 默认应用 → 按文件类型选择** | **设置页里根本看不到** |

改完注册表还要**通知资源管理器刷新**，否则更改不即时生效：

```powershell
Add-Type -Namespace W32 -Name Notify -MemberDefinition `
  '[DllImport("shell32.dll", CharSet=CharSet.Auto)] public static extern void SHChangeNotify(int a, uint b, IntPtr c, IntPtr d);'
[W32.Notify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
```

### 5.12 注册表写对 ≠ 真的能用

验证关联是否生效，**不能只看注册表**。可靠做法是实际启动一次并观察是否产生新进程：

```powershell
$before = @{}; Get-Process | ForEach-Object { $before[$_.Id] = $_.Name }
Start-Process <被关联的文件或 exe>
Start-Sleep 8
$new = Get-Process | Where-Object { -not $before.ContainsKey($_.Id) }
$new | Select-Object -ExpandProperty Name -Unique      # 有输出才算真的打开成功
$new | Stop-Process -Force                             # 测试后清理
```

注意要先清掉可能已运行的同一程序（单实例应用会把测试"吞掉"，产生假阴性）。

### 5.13 卸载便携程序后，关联会断

便携版"删文件夹即卸载"很方便，但**注册表里的关联不会跟着消失**，会留下三种残留：

| 残留 | 后果 | 严重性 |
|---|---|---|
| `UserChoice` 指向已删程序 | **默认打开方式失效**，双击文件没反应或报错 | 高，必须修 |
| ProgID 指向已删程序，但已无扩展名引用 | 无害，但会出现在"打开方式"列表里 | 低，可清理 |
| `RegisteredApplications` / `Capabilities` 指向已删程序 | 设置页里显示一个不存在的程序 | 低，可清理 |

**因此删程序后应主动检查关联**，而不是等用户发现双击打不开：

```powershell
# 对每个关心的扩展名，看它的默认 ProgID 指向的 exe 是否还存在
foreach ($ext in '.md','.png','.mp4') {
    $uc  = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $cls = (Get-ItemProperty "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue).'(default)'
    $progId = if ($uc) { $uc } else { $cls }
    $cmd = (Get-ItemProperty "HKCU:\Software\Classes\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    "{0,-8} {1,-30} {2}" -f $ext, $progId, $cmd
}
```

### 5.14 枚举注册表：`reg query` 比 PowerShell 快两个数量级

**这是我在实际操作中踩的坑，代价是 281 秒。**

清理关联残留需要遍历 `HKCU\Software\Classes`（本机 853 个子键）。用 PowerShell：

```powershell
# 慢：853 个键逐一 Get-ItemProperty，实测 281 秒
foreach ($s in Get-ChildItem 'HKCU:\Software\Classes') {
    try { $c = (Get-ItemProperty "$($s.PSPath)\shell\open\command" -ErrorAction Stop).'(default)' } catch { continue }
}
```

改用原生 `reg query` 是**秒级**：

```powershell
# 快：原生 exe，同样的信息
reg query 'HKCU\Software\Classes' /s /ve
```

> **注意 `reg query /f` 无法跨反斜杠匹配键名** —— `/f 'shell\open\command' /k` 只匹配
> **单层**键名，永远返回 0 条。要按路径匹配必须逐层查，或直接读全量输出再过滤。

**结论**：注册表全量扫描一律优先 `reg query`；只在需要类型化访问单个已知键时才用 PowerShell cmdlet。

---

## 6. 已固化为 Skill

上述全部方法论已整理为两个独立项目并推入仓库。

### 6.1 `skills/win-dev-environment` —— 开发环境

[仓库地址](https://github.com/Gvmeakiss/gvmeakiss-notebook/tree/main/skills/win-dev-environment)（四件套齐全）

| 文件 | 用途 |
|---|---|
| `SKILL.md` | 方法论与判断清单（标准 frontmatter，可被 Skill 工具加载） |
| `README.md` | 详细说明、参数速查、踩坑记录 |
| `scripts/audit-env.ps1` | 只读审计；含 `IsWindows11OrLater` 判定与镜像/DNS 可达性 |
| `scripts/fix-env.ps1` | 修复 7 类陷阱，幂等，支持 `-WhatIf` 干跑 |
| `scripts/setup-langs.ps1` | 装 8 种语言 + 配 6 个镜像源 |
| `scripts/verify-env.ps1` | **真实编译运行**每种语言，并实际拉取依赖验证镜像链路 |

### 6.2 `skills/win-portable-apps` —— 便携软件安装

[仓库地址](https://github.com/Gvmeakiss/gvmeakiss-notebook/tree/main/skills/win-portable-apps)（四件套齐全）

来自"帮我安装一下便捷使用电脑的软件"那次会话。收录在没有 winget、没有管理员权限的
Windows 上装好日常软件的完整方法。

| 文件 | 用途 |
|---|---|
| `check-software.ps1` | 只读盘点：便携应用 + Scoop + MSI + PATH 覆盖 + 文件关联状态 |
| `install-portable.ps1` | 清单式安装：下载 → **校验 SHA256** → 解压 → 折叠目录 → 快捷方式 → PATH |
| `set-app-associations.ps1` | 备份注册表、注册 ProgID、精确列出仍需手动点的扩展名 |
| `apps.example.json` | 清单示例（7 个常用程序，按用途分组） |

三条关键判断：

1. **便携版是非管理员账户的可行路线** —— MSI 需提权，非管理员跑会静默失败或留半成品
2. **便携软件不出现在"应用和功能"里** —— 只查系统列表会得出"什么都没装"的错误结论
3. **默认程序无法脚本设置** —— 见 §5.9

装好的程序按用途分组（同一用途多个不是冗余，各有明显更合适的场景）：
文本 Notepad++ / Markdown MarkText / 图片 JPEGView·nomacs·ImageGlass /
音视频 mpv·MPC-BE / 存储 rclone。

### 6.3 实用价值

换台机器时跑几条命令即可复现；给别人配环境时不用重讲一遍。

---

## 7. 可复现命令

```powershell
# 0) 前置：Scoop（用户级，无需管理员）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
irm get.scoop.sh | iex

# 1) 审计（只读）
pwsh -File skills/win-dev-environment/scripts/audit-env.ps1

# 2) 修复已知陷阱（先干跑）
pwsh -File skills/win-dev-environment/scripts/fix-env.ps1 -WhatIf
pwsh -File skills/win-dev-environment/scripts/fix-env.ps1

# 3) 安装工具链 + 配镜像
pwsh -File skills/win-dev-environment/scripts/setup-langs.ps1

# 4) 验证：真实编译每种语言
pwsh -File skills/win-dev-environment/scripts/verify-env.ps1
```

**开新终端再使用工具** —— 环境变量变更不影响已运行的进程。

### GitHub 认证（多账号机器）

```powershell
gh auth login          # 选 GitHub.com → HTTPS → Login with a web browser
                       # 记下 8 位设备码，在浏览器输入；务必确认账号正确
gh auth setup-git      # 让 token 直接供 git 使用
```

---

## 8. 未完成事项

| 项 | 说明 | 影响 |
|---|---|---|
| **SSH 公钥未添加** | https://github.com/settings/keys；指纹 `SHA256:/2xUwgYsW6fqnvuecMQIfCdN6osjjdw3fpohJQ/c+dQ` | 无。`gh` token 已可推送，SSH 只是第二条通道 |
| **未配置 SSH passphrase** | 当前密钥无口令 | 私钥被拷贝即可用。介意则 `ssh-keygen -p -f <key>` 补上 |
| **未配置 `credential.helper` 单一化** | GCM 与 gh 两个 helper 并存 | 低。若 gh token 过期，GCM 可能回落到浏览器账号导致混淆 |
| **computer use 未安装** | 见下 | 见下 |

### 关于 computer use（结论：暂不安装）

DSH **本身已内置** computer-use 插件（`dsh-experimental-computer-use-cua-driver-mcp`），
但需要一个外部可执行文件 **Cua Driver**（`pip install cua-driver`）。三个硬阻塞：

1. **社区 Windows 插件要求 Windows 11** —— 本机是 build 19045
2. **Cua Driver 在 Windows 10 19045 上有已知缺陷**：
   - [#2298](https://github.com/trycua/cua/issues/2298) `0.8.3 守护进程崩溃 0xC0000005`（你的确切版本号）
   - [#2113](https://github.com/trycua/cua/issues/2113) `0.7.0 枚举窗口/应用/桌面状态挂死`
   - [#2066](https://github.com/trycua/cua/issues/2066) Windows 二进制**未签名**，UIAccess 无法启动
3. **上游自己承认从未在 Windows 验收**：其 `WINDOWS_TEST.md` 开头即 `BLOCKED — no Windows GUI test environment available`

**替代方案**：PowerShell 脚本（确定性、可审计、可重放，比截图驱动的 computer use **更可靠**）
+ 浏览器自动化（Playwright）+ 截图交给 AI 读。

想零风险验证可行性，可只跑 `pip install cua-driver && cua-driver doctor --json`，不接 DSH。

---

## 9. 仓库侧成果

| 项目 | 内容 |
|---|---|
| **CI** | 新增 `.github/workflows/tests.yml`；三套 `node --test` 在 Linux 上运行，**与 Windows 本地互补**（POSIX 权限位断言在 Linux 真正生效，在 Windows 自动跳过） |
| **跨平台修复** | `merlin` 测试权限位断言改为按平台条件执行（Windows 不支持 POSIX 权限位，`stat().mode` 恒为 `0o666`） |
| **`.gitattributes`** | 文本统一 LF 入库；你在 Windows、仓库原在 macOS 维护，可消除整文件差异 |
| **`.gitignore`** | 补充 Windows 产物、构建产物（`dist/`、`.next/`、`*.tsbuildinfo`）、编辑器目录、日志 |
| **PR #3 合并** | 「稽核工作台」105 个文件的工程搁置 3 周且 `CONFLICTING`。**只摘取 `audit-workbench/` 目录**重建，剔除对 `merlin/`、`shadowrocket/`、根目录的旧快照改动 —— **整分支合并会误删 main 上已有的 43 个测试与配置** |
| **PR #1 关闭** | 内容已被 main 的完整重写版取代 |
| **分支清理** | 删除 2 个陈旧 `agent/*` 分支，仓库只剩 `main` |
| **新增 Skill 项目** | 两个：`skills/win-dev-environment`（开发环境）与 `skills/win-portable-apps`（便携软件） |

### 验证结果

| 检查 | 结果 |
|---|---|
| `audit-workbench` 测试 | **36/36 通过**（修复 Windows 编码问题前为 35/36） |
| 三套仓库测试合计 | **43/43 通过** |
| 环境验证脚本 | **33 项检查通过**（真实编译 7 种语言） |
| 敏感信息扫描 | 全部项目无泄漏 |
| CI | main 上全部 success |

---

## 10. 经验总结

1. **先证明"真的缺失"，再动手装。** Windows 上大量"没装"是假象，直接重装会浪费大量时间。
2. **版本号不是证据。** 工具链可以正常打印 `--version` 却完全不可用 —— 必须真实编译一次。
3. **报错位置 ≠ 故障位置。** `dlltool` 缺失报在依赖构建深处；编码问题报在业务代码里。
4. **平台差异要被识别为差异，而不是缺陷。** POSIX 权限位断言、GBK 默认编码，都是"代码在别的系统上没问题"的典型。
5. **凭据问题优先怀疑"环境"而非"配置"。** 两个 GitHub 账号 + 浏览器登录态，比任何 git config 都更可能是根因。
6. **删除前先证明可重建。** 合并 PR 前比对内容，删克隆前比对远端 HEAD —— 都是为了避免不可逆损失。
