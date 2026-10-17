# win-ai-gaming-setup

> **新 Windows 机器一键配置：AI 开发 + 游戏环境 + 系统优化**
>
> 一台刚装好系统的 Windows 电脑，一条命令配成能干活的机器 —— 补齐 AI 开发工具链、装上常用便携软件、做完安全的系统优化。全程先快照、可回滚。
>
> 方法论的判断依据见 [SKILL.md](./SKILL.md)；这里只讲**装了什么、配了什么、怎么跑、坏了怎么办**。

```powershell
# 在一台新 Windows 机器上（建议 PowerShell 7 + 管理员）
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1
```

跑完输出一张 PASS/FAIL 表；**退出码 0 = 选中的阶段全过**，非 0 = 有阶段失败（便于脚本串联）。

---

## 快速索引

| 我想… | 看这里 |
|---|---|
| 知道一条命令能得到什么 | [一、总览](#一总览一条命令能得到什么) · [三、七个阶段](#三七个阶段) |
| 看装了哪些软件、配了哪些项 | [四、装了什么](#四装了什么完整清单) · [五、配了什么](#五配了什么完整清单) |
| 查参数怎么组合 | [六、参数](#六参数) |
| 跑完还要做什么 | [七、跑完必须做的三件事](#七跑完必须做的三件事脚本代替不了) |
| 坏了要回滚 | [八、坏了怎么回滚](#八坏了怎么回滚) |
| 单独用某个工具脚本 | [九、工具箱](#九工具箱14-个脚本按用途分组) |
| 搞不清"谁在跑、结果算不算数" | [二、运行上下文](#二运行上下文为什么同一段代码结果不同) |

---

## 一、总览：一条命令能得到什么

| 维度 | 内容 | 规模 |
|---|---|---|
| **装什么** | 引导依赖 4 项 + 开发工具链 7 项 + 编辑器/终端 2 项 + 便携软件 4 项 | **17 项** |
| **配什么** | 开发环境 6 类 + 系统优化 6 类 + 文件关联 | **13 类** |
| **验什么** | 开发环境 6 类 + 软件清单 + 输入法 + 服务漂移 + **tune 存活检查 15 项** + **脚本双宿主校验** | **49 项检查** |
| **不碰什么** | 不禁用服务、不关 UAC、不改 DPI/分辨率、不动更新策略、不关休眠/快速启动 | — |
| **可回滚** | 改动前自动拍服务 + 自启项快照，可逐项对比、按基线还原 | — |

---

## 二、运行上下文（为什么同一段代码结果不同）

> **这是本技能最容易被搞错的一层，也是两次真实误判的根因。**
> 判断任何结果之前，先问：**这段代码是在哪个格子里跑的？**

| 谁在运行 | 宿主 | 提权 | 关键约束 |
|---|---|---|---|
| 你手动敲 `pwsh` | **PS 7** | 看窗口 | 最宽松，**但不能代表其它格** |
| `setup.ps1` 及子脚本 | **PS 7**；没有 pwsh 时**静默降级**到 5.1 | 通常提权 | 日常运行几乎不走 5.1 分支 ⇒ **5.1 的问题长期不暴露** |
| **计划任务** | **永远 PS 5.1** | 非提权（`RunLevel=Limited`） | 脚本必须 ASCII-only 或带 BOM；参数栏不走 Shell（重定向无效）；工作目录是 `C:\Windows\System32` |
| 登录脚本 / 启动文件夹 | 取决于 `.lnk` 怎么调 | 非提权 | 与 explorer 同级，能建出用户可见的驱动器映射 |
| explorer.exe / 你双击运行 | — | **非提权** | **只认非提权侧建的驱动器映射** |
| 提权 PowerShell | PS 7 或 5.1 | **提权** | 同一会话 Id，**但映射命名空间不同** ⇒ `Get-SmbMapping` 为空不代表用户没映射 |

**三条直接推论：**

1. **验收要在"目标格"里做** —— 验计划任务就得在计划任务上下文验；在提权窗口里验非提权行为一定误判。
2. **写完任何 `.ps1` 先跑 `check-script-hygiene.ps1`** —— 它把"两个宿主会不会分歧"变成一次秒级检查。
3. **`$LASTEXITCODE` 在进程内调用脚本时不会更新** —— 拿子脚本成败要么真起子进程，要么解析它自己的输出。

---

## 三、七个阶段

| 阶段 | 内容 | 管理员 | 可回滚 |
|---|---|---|---|
| `check` | **引导安装 + 检查**：PowerShell 7 / Scoop / git / 7-Zip / 长路径 / 开发者模式 / github 连通 / 磁盘 / 提权 / build+UBR | 部分 | — |
| `dev` | Scoop 装 `python nodejs go cmake dotnet-sdk mingw uv`（+ `rust`，由 `setup-langs.ps1` 默认集带入）+ **VS Code / Windows Terminal** + 国内镜像（pip/npm/go/cargo/HF）；修 PATH、Store 存根、凭据助手。**收尾逐项回读镜像真实状态** | 部分 | 是（Scoop 卸载） |
| `apps` | 按 `apps.json` 装便携软件：下载 → **SHA256 校验** → 解压 → 折叠目录 → 快捷方式 / PATH | 否 | 是（删目录） |
| `drivers` | 故障设备清单（含故障码）+ Windows 更新里的驱动更新；`-InstallDrivers` 直接装 | 是 | 驱动可在设备管理器回滚 |
| `tune` | **先快照**，再改：GameDVR 关闭、MMCSS 调优（**含 `Tasks\Games` 四项**）、关闭广告推荐 / 开始菜单联网搜索 / 遥测；结束前**回读 `sc query MMCSS` 是否 RUNNING**——服务停则 MMCSS 值**全部无效**，且它是引导期驱动、**只能靠重启加载**；（可选）高性能电源计划、鼠标加速 | 是 | 是（`compare-services.ps1 -Restore`） |
| `link` | 注册关联（`-RegisterAssociations`）+ 报告哪些类型需手动点一次 + 孤儿关联检查 | 否 | 是（有注册表备份） |
| `verify` | **六路验收** + 软件清单 + 输入法健康 + 服务基线漂移；总 **49 项检查**（见下表） | 否 | — |

`verify` 阶段具体验什么：

| 组别 | 项数 | 判据要点 |
|---|---|---|
| `hygiene` | 1 | 每个 `.ps1` 在 **PS 7 与 PS 5.1 下都能解析**（编码 + 双宿主检查） |
| `tweaks` | 15 | 含 **MMCSS 驱动是否真的在跑**（只看注册表会漏掉"值在、服务停"） |
| 各语言链 | 25 | 真编译真运行，不看 `--version` |
| 其它 | 8 | 软件清单 / 输入法 / 服务漂移 / git / gh / ssh |

---

## 四、装了什么（完整清单）

### 4.1 引导依赖 —— `check` 阶段缺什么补什么

| 软件 | 用途 | 安装方式 | 提权 |
|---|---|---|---|
| **PowerShell 7** | 脚本运行时。**没有它时全流程会静默降级到 5.1**，而 5.1 对无 BOM 的 UTF-8 脚本会解析失败 | `scoop install pwsh` | 否 |
| **Scoop** | 用户级包管理器，后续一切软件的底座 | 官方安装方式 | 否 |
| **git** | 版本控制；Scoop bucket 本身也依赖它 | `scoop install git` | 否 |
| **7-Zip** | 解压 `.7z` 资产（便携软件里有） | `scoop install 7zip` | 否 |

### 4.2 开发工具链 —— `dev` 阶段，Scoop main bucket

| 包 | 用途 |
|---|---|
| `python` | 主力语言（AI / 数据处理 / 脚本） |
| `nodejs` | 前端与 Node 工具链 |
| `go` | 单文件二进制工具开发 |
| `cmake` | C/C++ 构建系统 |
| `dotnet-sdk` | .NET 开发 |
| `mingw` | Windows 上的 GCC 工具链 |
| `uv` | 极快的 Python 包/虚拟环境管理器 |

> `rust` 由配套脚本 `setup-langs.ps1` 处理，且**已纳入默认集** —— `verify-env.ps1` 会检查它，早先不在默认列表里会导致默认流程**验收自失败**。不想付这 ~1 GB 下载就加 `-SkipRust`。
>
> ⚠ **Scoop 包名与俗称不同**：`node` 实为 `nodejs`、`dotnet` 实为 `dotnet-sdk`。
> `scoop install` **遇到一个不存在的清单会中止整批**，所以名字写错会让整套工具链一个都装不上，而流程仍一路报成功。`setup.ps1` 现已内置别名归一化（`node` / `dotnet` / `python3` / `golang`），并改为**逐个安装 + 逐个回读**，一个失败只损失一个包。

### 4.3 编辑器与终端 —— `dev` 阶段，Scoop extras

| 软件 | 用途 | 跳过方式 |
|---|---|---|
| **VS Code** | 主编辑器 | `-NoEditor` |
| **Windows Terminal** | 终端（`pwsh` 的体验依赖它） | `-NoEditor` |

### 4.4 便携软件 —— `apps` 阶段，按 `apps.json` 装

**每一个都强制 SHA256 校验**（脚本默认拒绝无哈希条目），流程：下载 → 校验 → 解压 → 折叠单层目录 → 建快捷方式 / 加 PATH。

| 软件 | 用途 | 关联的文件类型 |
|---|---|---|
| **JPEGView** | 看图。秒开，扛得住超大文件夹 | `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.webp` `.tif` `.tiff` |
| **MPC-BE** | 音视频播放，带正常播放器 UI（播放列表、变速、字幕） | `.mp4` `.mkv` `.avi` `.mov` `.webm` `.mp3` `.flac` `.wav` `.m4a` |
| **MarkText** | Markdown 实时预览编辑器。**条件安装** —— 先读下方取舍说明再决定装不装 | `.md` `.markdown` |
| **rclone** | 命令行同步/备份到 NAS（SMB / WebDAV） | —（命令行工具，进 PATH） |

> ⚠ **解压器按容器选**：`.zip` 用系统内置的 ZIP 支持（**不需要任何外部工具**），`.7z` 才需要 7-Zip。
> **`7zr.exe` 是精简版、没有 ZIP 编解码器** —— 早先误以为它能通吃，结果唯一的 `.7z` 装好了、三个 `.zip` 全挂（exit 2）。
>
> ⚠ **清单里的 `exe` 是相对安装根目录的路径**：包内有多个顶层目录时"折叠单层"不会触发（JPEGView 就有 `JPEGView32` / `JPEGView32-WinXP` / `JPEGView64` 三个），必须写 `JPEGView64\JPEGView.exe`；消费方也不能用 `Split-Path -Leaf` 取叶子名，那会丢掉子目录。
>
> ⚠ **Markdown 编辑器是取舍，不是越花哨越好**：MarkText 是 Electron 应用，**是本清单里启动最慢的一个**，界面也常被嫌旧。如果用户的诉求是"**启动快、界面简单**"，正确的答案是 **Notepad++**（原生、自带 Markdown 高亮、零插件即可用），而不是再找一个界面更漂亮的编辑器；需要实时预览就用已装的 VS Code（`Ctrl+Shift+V`）。**先问清诉求再装** —— 实测有机器最终就是**不装 MarkText**（`apps.json` 仍声明它，属"可选"而非"必装"，`check-software.ps1` 不会因此报缺）。
>
> **这个"可选"现在由代码强制**：`apps.json` 里该条目标了 `"optional": true`，`install-portable.ps1` **默认跳过**它并打印跳过原因；
> 要装就加 `-IncludeOptionalApps`（经 `setup.ps1`）或 `-Only MarkText`（直接调 `install-portable.ps1`）。
> 早先文档写"条件安装"而代码无条件安装 —— 那种不一致会让文档描述的程序和实际运行的不是同一个。

> 便携软件**不会出现在系统「应用列表」里**，盘点要用 `check-software.ps1` 扫目录。

### 4.5 需要手动装的（有意不自动化）

| 项目 | 为什么手动 |
|---|---|
| **GPU 驱动 + CUDA / PyTorch** | 厂商相关、体积大；且 torch 构建要按 CUDA 版本选。先装驱动，再选构建 |
| **WSL2 / Docker** | AI 开发的常见需求，但需要提权 + 虚拟化支持，交给你决定 |
| **厂商驱动**（蓝牙/网卡等） | 找不到时用 Microsoft Update Catalog 检索，**装前必须确认 INF 里含你的硬件 ID** |

### 4.6 不想用 scoop 的话（WinGet / 官方安装器路线）

scoop 在本技能里是**手段**（保证工具装得上），不是目的。如果你更喜欢 WinGet 或官方安装器，**结果是等价的** —— 只要下表这些"仪器"到位、镜像生效即可。实测有一台机器就是这么配的：**17 项里 16 项到位**（唯一缺的正是 scoop 本身），便携软件版本与 `apps.json` 声明逐一吻合。

代价是**技能的自动安装阶段用不了**（`setup.ps1` 有 44 处引用 scoop），但**验收与故障处置工具链完整可用**（`verify-env.ps1` 与快照/回滚/输入法/设备复位/关联这 6 个脚本都是 0 处引用）。

| 检查项 | 判据（不是"路径在不在"，而是"能不能调出版本号"） |
|---|---|
| 引导依赖 | `pwsh` / `git --version` / `7z`（可选：`scoop`） |
| 语言链 | `python --version`、`node --version`、`go version`、`cmake --version`、`dotnet --version`、`gcc -dumpfullversion -dumpversion`、`uv --version`、`rustc --version` |
| 编辑器 | `code --version`、Windows Terminal |
| 便携软件 | 扫 `~\Apps\` 下 `apps.json` 声明的相对路径 + 读文件版本（**它们不进系统"应用列表"**） |
| 镜像 | `pip config get global.index-url`、`npm config get registry`、`go env GOPROXY`、`cargo` 的 `config.toml`（注意 `CARGO_HOME` 未必是 `~\.cargo`）、`HF_ENDPOINT` |

> ⚠ **不要用 `Test-Path` 判断工具链**：它把 `*` 当通配符，而且"路径存在"不等于"能跑"。
> 完整对照实例与方法见 [`docs/windows-environment-setup-win11.md`](../../docs/windows-environment-setup-win11.md) §5。

---

## 五、配了什么（完整清单）

### 5.1 开发环境（`check` + `dev` 阶段）

| 配置项 | 具体动作 | 为什么 |
|---|---|---|
| **长路径支持** | `git config --global core.longpaths true` + `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled=1` | AI 仓库嵌套深度经常超过 260 字符 |
| **开发者模式** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense=1` | HuggingFace 缓存 / pnpm 需要建符号链接 |
| **执行策略** | 当前用户设为 `RemoteSigned` | Scoop 安装所需 |
| **国内镜像** | **pip**=清华 · **npm**=npmmirror · **go**=goproxy.cn · **cargo**=rsproxy.cn · **HuggingFace**=`HF_ENDPOINT=hf-mirror.com` | 不走镜像基本下不动。**收尾会逐项回读真实值**——每个镜像都被"工具在不在 PATH"守卫着，工具没装成功就整段跳过，而硬编码的汇总行会谎报"已生效"。cargo 配置写入 `CARGO_HOME`（scoop 的 rustup 包把它指向 `scoop\persist\rustup\`，**不是** `~\.cargo`） |
| **PATH / Store 存根** | `fix-env.ps1` 修「装了却找不到」、应用执行别名劫持 | Windows 的 Store 存根会劫持 `python` 等命令 |
| **凭据助手** | 修正 git credential helper | — |

### 5.2 系统优化 —— `tune` 阶段

**先拍快照再动手**（`snapshot-services.ps1`，导出服务启动类型 + 自启项）。每一条都是**单个注册表写入，逐条报告**；`-WhatIf` 可先看清单。

#### A. 游戏相关

| 项 | 动作 | 好处 |
|---|---|---|
| **Xbox Game DVR** | 策略层 `AllowGameDVR=0` + 用户层 `GameDVR_Enabled=0`、`AppCaptureEnabled=0` | 去掉后台录制，直接换帧数 |
| **MMCSS 多媒体调度** | `SystemResponsiveness=10`（默认 20）、`NetworkThrottlingIndex=0xffffffff` | 游戏线程优先级更高；去掉网络限流 |
| **MMCSS `Games` 任务** | `GPU Priority=8`、`Priority=6`、`Scheduling Category=High`、`SFIO Priority=High` | 让游戏进程拿到多媒体调度优先级 |

#### B. 广告与推荐（全部关闭）

| 项 | 动作 |
|---|---|
| 静默安装推广 App | `SilentInstalledAppsEnabled=0` + 策略 `DisableWindowsConsumerFeatures=1` |
| 开始菜单建议/推荐 | `SystemPaneSuggestionsEnabled=0`、`SubscribedContent-338388/338389=0` |
| 锁屏广告 | `SubscribedContent-338387=0`、`RotatingLockScreenOverlayEnabled=0` |
| Windows 提示 | `SoftLandingEnabled=0` |
| 资源管理器同步提供程序广告 | `ShowSyncProviderNotifications=0` |
| 开始菜单 Bing 联网搜索 | **走策略键**：`DisableSearchBoxSuggestions=1`（`HKCU\Software\Policies\...\Explorer`）+ `ConnectedSearchUseWeb=0`、`AllowCortana=0`（`HKLM\...\Policies\...\Windows Search`） |

> 即 SKILL.md 里说的「CDM 9 项」。
>
> ⚠ **联网搜索为什么不用 `BingSearchEnabled`**：`HKCU\...\CurrentVersion\Search` 这个键在 Windows 11 24H2+ 上**会被内核层拒绝写入**（`reg import` 报 `Not all data was successfully written to the registry`），而它的 ACL 看着仍是当前用户 `FullControl` —— 不是 ACL 问题，夺所有权也没用。策略键实测可写，且优先级高于用户作用域，**不是降级**。`verify-env.ps1` 对这两条路径**任一生效即判 PASS**。

#### C. 遥测

| 项 | 动作 |
|---|---|
| 诊断数据 | 策略 `AllowTelemetry=0` —— **是改策略，不是去杀服务** |

#### D. 可选开关（默认关，按需打开）

| 参数 | 效果 | 为什么默认关 |
|---|---|---|
| `-DisableMouseAcceleration` | 鼠标加速曲线清零，指针 1:1 | 操作手感偏好 |
| `-HighPerformancePowerPlan` | 切到高性能电源计划 | 笔记本费电 |
| `-InstallDrivers` | 实际安装 Windows 更新提供的驱动 | 驱动更新有风险 |
| `-RegisterAssociations` | 写文件关联注册（**只写 HKCU**） | 属用户取舍 |
| `-SkipTweaks` | 只快照、不改系统 | — |

### 5.3 文件关联（`link` 阶段）

让上一步装的程序出现在「打开方式」候选里，并报告**哪些类型还需你手动点一次**。

> Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，官方 COM API 在 Win10 上返回 `0x80070002` 且不生效。
> **脚本只能让程序出现在候选里，设为默认必须手动点一次**（每个类型一次，长期有效）。

### 5.4 明确不做的（这几项是用户取舍，不是「优化」）

- **不禁用任何服务** —— 按需启动的服务禁用后省不到性能，却会把输入法 / 相机 / 手柄搞坏（代价表见 SKILL.md 第一条纪律）
- **不关 UAC、不改 DPI/分辨率、不动 Windows 更新策略**
- **不关休眠 / 快速启动** —— 关休眠会连带关掉快速启动，反而让开机变慢
- **不装第三方「优化大师 / 加速器」** —— 本方案本身就是那类东西的安全替代

---

## 六、参数

### 6.1 `setup.ps1` 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `check,dev,apps,drivers,tune,link,verify` 任意组合 |
| `-Manifest` | `apps.json`（技能根目录） | 便携软件清单 |
| `-Destination` | `%USERPROFILE%\Apps` | 便携软件根目录 |
| `-SnapshotDir` | `<Destination>\_backup` | 快照与关联备份位置 |
| `-Languages` | `python,nodejs,go,cmake,dotnet-sdk,mingw,uv` | 开发阶段要装的 Scoop 包。**必须是真实 scoop 清单名**；`node` / `dotnet` / `python3` / `golang` 会被自动归一化 |
| `-NoEditor` | 关 | 跳过 VS Code + Windows Terminal |
| `-IncludeOptionalApps` | 关 | 也安装清单里标了 `"optional": true` 的条目（当前只有 MarkText）。**默认跳过**，因为它的 notes 明确写着"安装前先问用户"。给 `install-portable.ps1` 用 `-Only MarkText` 点名也会装 |
| `-InstallDrivers` | 关 | `drivers` 阶段实际安装 Windows 更新提供的驱动 |
| `-DisableMouseAcceleration` | 关 | 把鼠标加速曲线清零（FPS 习惯） |
| `-HighPerformancePowerPlan` | 关 | 打开才切高性能（笔记本费电） |
| `-RegisterAssociations` | 关 | 打开才写关联注册（只写 HKCU） |
| `-SkipTweaks` | 关 | 只快照、不改系统 |
| `-WhatIf` | — | 预演，什么都不改 |

### 6.2 常用组合

```powershell
# 只看这台机器缺什么
pwsh -File scripts/setup.ps1 -Phase check

# 开发环境 + 软件（最常用）
pwsh -File scripts/setup.ps1 -Phase dev,apps

# 先看看 tune 要改什么
pwsh -File scripts/setup.ps1 -Phase tune -WhatIf

# 只验收
pwsh -File scripts/setup.ps1 -Phase verify
```

---

## 七、跑完必须做的三件事（脚本代替不了）

1. **重启，然后新开一个终端** —— PATH 与输入法栈都在登录时重建；不重启就下结论是最常见的误判
2. **手动点一次默认程序** —— Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，脚本只能让程序出现在候选里。
   右键任意该类文件 → 打开方式 → 选择其他应用 → 选中 → 勾"始终使用此应用"（每个类型一次，长期有效）
3. **设备有故障码就复位** —— `pwsh -File scripts/reset-failed-devices.ps1 -Reset`（管理员）。
   脚本会**先试 `pnputil /restart-device`**（秒级、免重启），失败才降级到 disable/enable + 重扫；仍不行的先"完全关机"断电，再装厂商驱动

> ⚠️ **打完累积更新后，重跑一次 `verify-env.ps1`。**
> 实测两次：累积更新会**删掉** tune 阶段写入的注册表值 —— 不是改成别的值，是**直接删除**（`SystemResponsiveness`、`GlobalUserDisabled`、各项广告开关都中招过）。
> 所以那组 **tune 存活检查**把「值缺失」直接判为 `FAIL`：只看值等不等于期望值，会把「被删了」误判成「本来就没设置过」。
> 同一组检查还会验证 **MMCSS 驱动是否真的在跑** —— 光看注册表会漏掉「值在、服务停」这种失效。

---

## 八、坏了怎么回滚

```powershell
# 1) 对比：哪些被改了、哪些本来就这样
pwsh -File scripts/compare-services.ps1 -Snapshot "$env:USERPROFILE\Apps\_backup\services-snapshot.csv"

# 2) 预演回滚，确认改动项与预期一致
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf

# 3) 回滚（可只挑一项）
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -Only TabletInputService
```

**输入法坏了**走专用路径：

```powershell
pwsh -File scripts/diagnose-ime.ps1            # 诊断：服务/进程/语言栏模式/IFEO/策略，给结论
pwsh -File scripts/diagnose-ime.ps1 -Repair    # 修复（管理员），之后必须重启
```

**游戏崩溃 / 黑屏 / 进游戏就挂** —— 不是改回滚，而是显卡驱动挂起，走专用路径：

```powershell
# 1) 先取证：有没有内核看门狗转储（设备恢复后记录仍在）
Get-ChildItem C:\Windows\LiveKernelReports\WATCHDOG\*.dmp | Sort-Object LastWriteTime -Descending

# 2) 恢复设备（秒级，不用重启）
pnputil /restart-device "<InstanceId>"     # 或直接跑 reset-failed-devices.ps1 -Reset
```

仍反复的话按 `SKILL.md` 的「**显卡稳定性**」小节走：加大 `TdrDelay` → 关 AMD `EnableUlps` → 散热 / 驱动重装。

> 症状识别：**屏幕黑一下又恢复** = 又 TDR 了；**游戏分辨率/画质被改回通用值** = 显卡挂掉后游戏重跑了硬件检测，是症状不是原因。

---

## 九、工具箱（14 个脚本，按用途分组）

全部自包含、支持 `Get-Help`。除了 `setup.ps1` 是唯一入口，其余都能单独用。

### 9.1 开工前 —— 探明现状（只读）

| 脚本 | 用途 | 主要参数 |
|---|---|---|
| `check-script-hygiene.ps1` | **脚本体检**：每个 `.ps1` 的编码 + **PS 7 / PS 5.1 双宿主解析**（不执行，秒级） | `-Path` `-Recurse` |
| `audit-env.ps1` | 开发环境审计（工具链 / 镜像 / PATH / 存根） | `-Json` `-Languages` `-PackageManagers` |
| `check-software.ps1` | 软件盘点（含便携软件扫目录） | `-PortableRoot` `-Json` |
| `snapshot-services.ps1` | 改动前拍照：服务启动类型 + 自启项（只读） | `-OutDir` |
| `set-app-associations.ps1` | 关联现状报告（不加 `-Register` 就是只读） | `-CheckOnly` `-Apps` |

> **`check-script-hygiene.ps1` 为什么必须早跑**：无 BOM 的 UTF-8 脚本会被 `ParseFile` 按 UTF-8 读、
> 被 `powershell.exe -File` 按 ANSI 读 ⇒ **"校验通过"是假通过**，脚本随后在 5.1 里解析失败。
> 计划任务永远用 5.1，所以这类脚本会以 `0x1` 静默失败、而任务历史仍显示"成功"。
> 它已挂进 `verify-env.ps1`，**WARN 与 FAIL 都拦截**。

### 9.2 安装与修复

| 脚本 | 用途 | 主要参数 |
|---|---|---|
| `setup-langs.ps1` | 装语言工具链 + 配镜像（含 rust） | `-Packages` `-SkipMirrors` `-SkipRust` |
| `install-portable.ps1` | 清单式便携安装（**SHA256 必填**） | `-Manifest` `-Destination` `-Only` `-AllowUnverified` `-SkipShortcuts` |
| `fix-env.ps1` | 修「装了却找不到」：PATH / Store 存根 / 凭据助手（仅用户级） | `-SkipAliasRemoval` `-SkipCredentialFix` |

### 9.3 系统优化与回滚

| 脚本 | 用途 | 主要参数 |
|---|---|---|
| `compare-services.ps1` | 与快照逐项对比 / 按基线回滚 | `-Snapshot` `-Restore` `-Only` |
| `reset-failed-devices.ps1` | 设备故障码分诊与复位（先试 `pnputil /restart-device`，含 Code 31 `CM_PROB_FAILED_ADD`） | `-Reset` `-Class` |
| `clean-orphan-associations.ps1` | 卸载后的关联残留清理 | `-Clean` `-Root` |

### 9.4 故障处置与验收

| 脚本 | 用途 | 主要参数 |
|---|---|---|
| `diagnose-ime.ps1` | 输入法故障诊断与修复 | `-Repair` `-TargetStartType` |
| `verify-env.ps1` | **验收**：真编译真运行 + 软件清单 + 输入法 + 服务漂移 + tune 存活 15 项 + 脚本 hygiene | `-Languages` `-KeepArtifacts` |

> `verify-env.ps1` 的判据是**能跑**而不是**有版本号**：`--version` 有输出但 PATH 错、目标平台错、缺链接器、
> 镜像不通，都能骗过版本检查。所以它对每种语言做一次真实 build + run，并在需要时真的去拉一个依赖。
> **打完累积更新后值得重跑**（原因见第七节）。

---

## 十、环境与边界

| 限制 | 说明 |
|---|---|
| 系统 | Windows 10/11 |
| Shell | 建议 PowerShell 7+；**5.1 也能跑，但脚本必须 ASCII-only 或带 BOM** |
| `scoop` 缺失 | **`check` 阶段会自动安装**（用户级，无需提权；官方脚本 `get.scoop.sh`）。注意只有 `check` 会装 —— 直接单跑 `dev` 阶段时 `setup-langs.ps1` 会报 `scoop not found`，这是预期行为 |
| `.7z` 资产 | 需要 `7z`（`scoop install 7zip`）；`.zip` 不需要外部工具 |
| 脚本编码 | 本目录所有脚本均为 **ASCII-only**（英文），文档为中文 |
| 默认程序 | **无法脚本设置** —— `UserChoice` 的 Deny ACL + Hash |
| `rclone mount` | 需要 WinFsp（驱动安装需提权）；改用系统盘符映射 |
| 验证完成 | **需要重启** —— 登录会话状态不会自愈 |

---

<p align="right"><sub>方法论与判断依据 → <a href="./SKILL.md"><b>SKILL.md</b></a> · 踩坑实录 → <a href="../../docs/windows-environment-setup-win11.md"><b>docs/</b></a></sub></p>
