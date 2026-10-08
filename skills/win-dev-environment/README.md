# Windows 开发环境：审计 · 修复 · 验证

在 **非管理员** Windows 账户上，把开发环境从"什么都没有"做到"每种语言都能真实编译运行"，
并配好国内可用的镜像源。

本目录来自一次真实的全过程：一台 Windows 10 机器，**零编程语言环境**，账户**无管理员权限**，
网络存在 DNS 污染与端口封锁。过程中踩到的每个坑都记录在案，并固化成可重跑的脚本。

---

## 为什么需要这套东西

Windows 上"工具没装"的报告**大部分是假的**。真实原因通常只有四类，而报错信息与实际原因完全不符：

| 你看到的 | 真实原因 |
|---|---|
| `python` 提示"从 Microsoft Store 安装" | Python **已装好**，但 `WindowsApps` 里的 **0 字节别名存根**优先级高于任何 PATH |
| 所有 scoop 装的命令 `not recognized` | `~\scoop\shims` 不在 PATH，或**当前进程环境比配置更早** |
| 命令时有时无、重装无效 | GUI 父进程继承了**陈旧 PATH**，子进程跟着错 |
| 装好了但模块/脚本找不到 | 包管理器把可执行文件放进 `persist\` 等**未加入 PATH 的目录** |

**所以第一原则：任何"缺失"结论，都必须在排除 PATH 与存根问题之后才能成立。**

---

## 快速开始

```powershell
# 0) 前置：Scoop（用户级包管理器，无需管理员）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
irm get.scoop.sh | iex

# 1) 审计（只读，不改任何东西）
pwsh -File scripts/audit-env.ps1

# 2) 修复已知陷阱（先干跑确认）
pwsh -File scripts/fix-env.ps1 -WhatIf
pwsh -File scripts/fix-env.ps1

# 3) 安装语言工具链
pwsh -File scripts/setup-langs.ps1

# 4) 验证：真实编译运行每种语言
pwsh -File scripts/verify-env.ps1
```

> **开新终端再使用工具。** 环境变量变更不影响已运行的进程。

---

## 脚本

### `scripts/audit-env.ps1` — 只读审计

```powershell
pwsh -File scripts/audit-env.ps1
pwsh -File scripts/audit-env.ps1 -Json | Out-File audit.json
```

| 参数 | 说明 |
|---|---|
| `-Json` | 输出 JSON 而非人读报告 |
| `-Languages` | 限定探测的工具链 |
| `-PackageManagers` | 限定探测的包管理器 |

检查项：OS/硬件（**含 `IsWindows11OrLater`**）· 权限与 shell · 20 个工具链版本 ·
**PATH 重复与失效条目** · 用户环境变量 · 包管理器与缓存 · 磁盘占用 · **镜像可达性** · **DNS 解析**。

`IsWindows11OrLater` 单独列出：大量 GUI 自动化 / UIA 工具链**只支持 Windows 11（build 22000+）**。
先确认平台再决定技术路线，可以避免整条方案走死。

### `scripts/fix-env.ps1` — 修复已知缺陷

```powershell
pwsh -File scripts/fix-env.ps1 -WhatIf        # 干跑
pwsh -File scripts/fix-env.ps1                # 应用
pwsh -File scripts/fix-env.ps1 -SkipAliasRemoval -SkipCredentialFix
```

| 步骤 | 内容 |
|---|---|
| 1 | Scoop `shims` 目录加入用户 PATH |
| 2 | 移除 Store 的 `python.exe`/`python3.exe` 存根；补建真实 `python` shim |
| 3 | 报告重复/失效的 PATH 条目；创建会推迟出现的标准工具目录 |
| 4 | 标准工具目录（`~\go\bin`、`~\.dotnet\tools`） |
| 5 | 检查 git 凭据助手是否被 `credential-manager configure` 污染 |
| 6 | 检查 Rust GNU 目标所需的 `dlltool` 是否可用 |
| 7 | 广播环境变更，让新进程拿到新 PATH |

**幂等**，可反复运行。**只做用户级改动**，不提权、不写机器级注册表。
删除操作仅限上面明确列出的 Store 存根，且会先校验它确实是重解析点或 0 字节文件。

### `scripts/setup-langs.ps1` — 安装工具链

```powershell
pwsh -File scripts/setup-langs.ps1
pwsh -File scripts/setup-langs.ps1 -Packages python,node,go,rust,java
pwsh -File scripts/setup-langs.ps1 -SkipMirrors
```

| 逻辑语言 | 实际安装 |
|---|---|
| `python` | `python`（3.14.x） |
| `node` | `nodejs`（26.x） |
| `go` | `go`（1.27.x） |
| `java` | `temurin21-jdk`（JDK 21 LTS） |
| `cmake` | `cmake`（4.x） |
| `dotnet` | `dotnet-sdk`（10.x） |
| `mingw` | `mingw`（GCC 16.x，含 gdb/make/binutils） |
| `rust` | **rustup**（非 scoop 的 `rust`，见下） |

**为什么 Rust 不走 scoop：** scoop 的 `rust` 清单是 MSI。MSI 是机器级安装、需要提权，
非管理员账户会失败或留下半成品。本脚本改用 **rustup 安装 GNU 目标**
（`x86_64-pc-windows-gnu`），它完全安装在用户目录下，并**复用已装的 MinGW binutils**——
从而**完全避开需要管理员的 Visual Studio Build Tools**。

### `scripts/verify-env.ps1` — 真实编译验证

```powershell
pwsh -File scripts/verify-env.ps1
pwsh -File scripts/verify-env.ps1 -Languages python,go,rust
pwsh -File scripts/verify-env.ps1 -KeepArtifacts
```

| 语言 | 验证内容 |
|---|---|
| python | 运行脚本；**实测默认编码行为**；导入依赖 |
| node | `npm install` 一个真实包 → `require` 调用 → 打印 registry |
| go | `go get` 一个模块 → `go run` → 打印 GOPROXY |
| rust | `cargo add rand`（**会引入需要链接的依赖**）→ `cargo build` → 运行 |
| java | `javac` → `java` → `jar` 打包 → `java -jar` |
| dotnet | `dotnet new console` → build → run |
| cpp | `g++ -std=c++20` 编译运行 → CMake 配置+构建+运行 |

**为什么坚持真实编译：** 版本号不是证据。工具链可以正常打印 `--version` 却完全不可用
（PATH 错、目标平台错、缺链接器、镜像不通）。

**为什么 Rust 特意用 `rand`：** 它会引入 `getrandom`，其构建脚本在 GNU 目标上**需要 `dlltool`**。
空 crate 不会暴露这个问题 —— 而这正是实战中最容易踩的坑。

退出码：真失败才非零。**可选配置**（如未设置 SSH 密钥）只报 `INFO`，不让整体失败。

---

## 实战踩坑记录

每一条都曾产生**与实际原因不符的报错**，因此最耗排查时间。

### Python：Store 存根 + 区域编码

**存根劫持**——`WindowsApps\python.exe` 是 0 字节重解析点，优先级高于任何 PATH 条目。
删掉它，再补建真实 shim 即可。注意 **scoop 的 python 清单可能只建 `python3` 而不建 `python`**。

**区域编码**——中文 Windows 上 Python 默认用 **GBK** 读文件，于是：

```
UnicodeDecodeError: 'gbk' codec can't decode byte 0x9f in position 341
```

**代码在 macOS/Linux 上正常，Windows 上失败。** 正确修法是代码里显式 `encoding='utf-8'`：

```python
# 错误：依赖平台默认编码
path.read_text()
# 正确：跨平台一致
path.read_text(encoding='utf-8')
```

`PYTHONUTF8=1` 是辅助手段，**不能当唯一修法** —— CI 和别人的机器不会设它。

### Rust：`dlltool` 缺失

GNU 目标链接 proc-macro 时调用 `dlltool`。缺失时报错发生在**依赖构建的深处**：

```
error calling dlltool 'dlltool.exe': program not found
```

看起来像某个 crate 有问题，实际是 binutils 不在 PATH。装 MinGW 即可。

### Git：`credential-manager configure` 污染配置

该命令会做两件有害的事：

1. 往**系统级** `etc/gitconfig` 写入**空值** `credential.helper =`
2. 往全局配置追加**转义错误的绝对路径**（形如 `C:/Users/Your Name\\ scoop/...`，即路径里的空格被错误转义）

空值会让 git **忽略真正的 helper**，回退到终端询问 —— 表现像"凭据坏了"。

```powershell
git config --system --unset-all credential.helper
git config --global --unset-all credential.helper
# 然后只保留一条正确的
git config --global credential.helper manager
```

### 认证：浏览器登录态劫持 CLI 授权

HTTPS + Git Credential Manager 会打开浏览器 OAuth 页。**若浏览器已登录另一个账号，
GitHub 会直接用它批准请求**，于是永远拿不到目标账号的令牌。多账号机器上极隐蔽。

追踪日志里的证据形式：

```
OpenBrowserInternal: Opening browser using shell-execute:
  https://github.com/login/oauth/authorize?...
username=<另一个账号>
```

按推荐度排序的解法：

1. **`gh auth login` 设备码方式**——显式输入码，**不复用浏览器登录态**；
   之后 `gh auth setup-git`，token 直接供 git 使用
2. **SSH 密钥**——完全不走浏览器；注意见下条

### 端口 22 被封

国内网络常见：TCP 能连通，但握手被中途切断：

```
kex_exchange_identification: Connection closed by remote host
```

改用 GitHub 官方支持的 **`ssh.github.com:443`**，并**用官方公布的指纹校验主机密钥**：

| 算法 | 官方指纹 |
|---|---|
| ED25519 | `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` |
| ECDSA | `SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM` |
| RSA | `SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s` |

来源：[GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)

### SSH 密钥：`-N '""'` 的陷阱

生成无口令密钥时写成 `-N '""'`，外层单引号会让 **字面量两个引号** 成为口令。
结果是密钥**无法在非交互会话中签名**，而 GitHub 那端其实**已经**接受了它：

```
debug1: Server accepts key: ... SHA256:xxxx    <- GitHub 接受了
debug2: we did not send a packet, disable method  <- 但本地签名失败
```

正确写法是 PowerShell 原生的空字符串（不加外层引号）：

```powershell
ssh-keygen -t ed25519 -f <path> -N ""     # 不要写成 -N '""'
```

验证方式：`ssh-keygen -y -f <key>` 应**直接输出公钥、不提示口令**。

### PowerShell 脚本自身的坑

写这类脚本时最容易踩的四个：

```powershell
# 1) $PSCmdlet 只在 [CmdletBinding()] 函数内存在。普通函数里它是 $null，
#    调用 .ShouldProcess() 抛错；在 $ErrorActionPreference='Continue' 下静默中断，
#    表现为"函数体一行都没执行也没有任何报错"。
#    解法：脚本级捕获一次
$Cmdlet = $PSCmdlet
# 之后统一用 $Cmdlet.ShouldProcess(...)

# 2) [void](SomeFunction) 会丢弃该函数的全部输出，包括写在里面的提示信息
# 3) 哈希表裸键名不能含运算符字符
$h = @{ 'g++' = @('--version') }    # g++ 必须加引号

# 4) 脚本必须自己从注册表重建 PATH，否则 GUI 父进程的陈旧环境会让已装工具报告缺失
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path','Machine'),
    [Environment]::GetEnvironmentVariable('Path','User')
) | Where-Object { $_ }) -join ';'
```

第 1 和第 4 条都在本项目开发过程中真实触发过，且都**表现为错误的结论**而非报错 —— 值得单独记住。

---

## 镜像源

| 生态 | 配置位置 | 地址 |
|---|---|---|
| pip | `%APPDATA%\pip\pip.ini` | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| npm | npm 用户配置 | `https://registry.npmmirror.com` |
| Go | `go env -w` | `https://goproxy.cn,direct` |
| Cargo | `~/.cargo/config.toml` | `sparse+https://rsproxy.cn/index/` |
| rustup | `RUSTUP_DIST_SERVER` | `https://rsproxy.cn` |
| NuGet | `%APPDATA%\NuGet\NuGet.Config` | nuget.org 主 + 华为云备 |

**镜像"可达"不等于"可用"。** 验证脚本会**实际安装一个包 / 拉取一个模块**来证明链路真的通。

---

## 边界与限制

- **仅适用于 Windows**；macOS / Linux 的环境问题不适用本方法论
- 脚本**只做用户级改动**，绝不提权、不写机器级注册表
- 非管理员账户**无法**安装：MSVC 工具链、系统级软件、`%ProgramFiles%` 内的东西
- **管理员权限窗口无法被 GUI 自动化操作**（Windows 既定边界）
- 高级 GUI 自动化工具（如 Cua Driver）**通常只支持 Windows 11**；
  Windows 10 上存在已知崩溃/挂死缺陷，安装前务必确认平台
