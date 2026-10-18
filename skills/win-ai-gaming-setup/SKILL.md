---
name: win-ai-gaming-setup
description: 把一台刚装好系统的 Windows 电脑一条命令配置成「AI 开发 + 游戏」机并完成系统优化 —— 装开发工具链（Python/Node/Go/dotnet/cmake/mingw/uv）、装编辑器与便携软件、做安全的系统优化（GameDVR/MMCSS/广告推荐/遥测），出故障可按基线回滚。当出现"新电脑怎么配""新机一键配置""帮我装开发环境""装 Python/Node/Go/dotnet""装些好用的小软件""优化一下打游戏""优化后输入法没了/某个功能坏了""想关服务但不知道后果""游戏老是崩溃/黑屏一下又恢复/分辨率被改了"等诉求时使用。唯一入口是 scripts/setup.ps1（check/dev/apps/drivers/tune/link/verify 七个阶段，幂等、可 -WhatIf）；核心纪律只有三条：不碰按需启动的服务、动系统前先拍快照、改完必须重启再验证。游戏崩溃 / 显卡挂起 / TDR 走 SKILL.md 的「显卡稳定性」小节。
agent_created: true
---

# Windows 新机配置：AI 开发 + 游戏

## 目标（什么叫"配好了"）

一台新机器跑完 `setup.ps1` 后应当满足：

| 维度 | 完成标准 |
|---|---|
| 开发 | `scoop` 可用的语言工具链（python/node/go/cmake/dotnet/mingw），PATH 与 Store 存根已修好，**新开终端**里敲 `python --version` 有输出 |
| 软件 | 20 个（3 基础 + 2 压缩 + 8 开发 + 2 编辑器 + 5 便携）；每个都按安装路径回读 |
| 游戏 | GameDVR 关闭、MMCSS 优先级已调；**没有禁用任何服务** |
| 系统 | 改动前有快照，能逐项对比、能回滚 |
| 输入法 | 中文能打、`Win+空格` 能切（这条最容易被"优化"搞坏） |

## 四类覆盖（核对清单）

### ① 需要配置的环境

| 项 | 怎么做 | 阶段 |
|---|---|---|
| PowerShell 7 | 缺就用 Scoop 装（`scoop install pwsh`）；脚本在 5.1 下也能跑，会自动改用 `powershell.exe` 调子脚本 | `check` |
| Scoop | 缺就按官方式安装（用户级，免提权） | `check` |
| git | `scoop install git`（bucket 需要 git） | `check` |
| 7-Zip / WinRAR | `apps.json` 的 `source: winget` 条目（`7zip.7zip` / `RARLab.WinRAR`）；`check` 阶段先试 scoop，**失败即回落到 winget 条目**，最后按安装路径回读 | `check` + `apps` |
| **长路径** | `git config --global core.longpaths true` + `HKLM\...\FileSystem\LongPathsEnabled=1`（AI 仓库嵌套极深） | `check` |
| **开发者模式** | `AppModelUnlock\AllowDevelopmentWithoutDevLicense=1`（HF 缓存 / pnpm 要建符号链接） | `check` |
| 执行策略 | 当前用户 `RemoteSigned`（Scoop 安装所需） | `check` |
| 国内镜像 | **pip**=清华、**npm**=npmmirror、**go**=goproxy.cn、**cargo**=rsproxy.cn、**HuggingFace**=`HF_ENDPOINT=hf-mirror.com` | `dev` |
| PATH / Store 存根 / 凭据助手 | `fix-env.ps1` 修"装了却找不到"、别名劫持 | `dev` |
| GPU 驱动 + CUDA/torch | **不自动化**（厂商相关、体积大）：先装驱动，再按 CUDA 版本选 torch 构建 | 手动 |

### ② 安装的软件

| 类别 | 内容 | 来源 |
|---|---|---|
| 语言与构建工具 | python / nodejs / go / cmake / dotnet-sdk / mingw / **uv**（+ rust 由 `setup-langs.ps1` 处理） | Scoop main |
| 编辑器与终端 | **VS Code**、**Windows Terminal** | Scoop extras（`-NoEditor` 可跳过） |
| 压缩工具 | **7-Zip**（`winget`，同时是便携包的解压器）、**WinRAR**（`winget`） | `apps.json` 的 `source: winget` + `verifyPath` 回读 |
| 便携软件 | **JPEGView**（图片）、**MPC-BE**（音视频）、**Notepad++**（文本/代码/Markdown）、**rclone**（NAS 同步）、**TrafficMonitor**（任务栏 CPU/内存/网速） | `apps.json`，SHA256 校验 + `exe` 回读 |
| 可选 | GPU 栈、WSL2 / Docker（AI 常见需求，需提权与虚拟化） | 手动 |

### ③ 执行的命令

```powershell
# 全部（新机器就这一条）
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1
# 分阶段（-File 模式下逗号列表会被脚本自行拆分）
pwsh -File ...\setup.ps1 -Phase check
pwsh -File ...\setup.ps1 -Phase dev,apps
pwsh -File ...\setup.ps1 -Phase tune -WhatIf
pwsh -File ...\setup.ps1 -Phase verify
# 单件工具
pwsh -File ...\scripts\diagnose-ime.ps1 [-Repair]
pwsh -File ...\scripts\compare-services.ps1 -Snapshot <csv> [-Restore -Only X]
pwsh -File ...\scripts\reset-failed-devices.ps1 [-Reset]
```

### ④ 关闭的无效配置

`tune` 阶段一次做完（**每一条都是单个注册表写入，逐条报告**；`-WhatIf` 可先看清单）：

| 关闭项 | 好处 |
|---|---|
| GameDVR（策略 + 用户） | 去掉后台录制，直接换帧数 |
| MMCSS `SystemResponsiveness=10` / `NetworkThrottlingIndex=off` | 游戏线程优先级、去掉网络限流 |
| 消费级广告与推荐（`DisableWindowsConsumerFeatures` + CDM 9 项） | 不再静默装推广 App、开始菜单无推荐、无锁屏广告 |
| 资源管理器"同步提供程序"广告 | 去掉 OneDrive/Office 推广横幅 |
| 开始菜单 Bing 联网搜索 | 搜索只搜本机 |
| 遥测 `AllowTelemetry=0`（策略，**不是**去杀服务） | 少上报 |
| （可选）`-DisableMouseAcceleration` | 指针 1:1，FPS 习惯 |
| （可选）`-HighPerformancePowerPlan` | 高性能电源计划，笔记本费电所以默认关 |

**明确不做**（这几项是用户取舍，不是"无效配置"）：禁用任何服务、关 UAC、改 DPI/分辨率、关 Windows 更新、关休眠/快速启动。

### 接手一台"已经被优化过"的机器时

如果前一个优化脚本顺手关掉了更新策略 / UWP 后台 / 搜索索引，按需恢复（均需管理员）：

```powershell
# 恢复 Windows 更新管线（恢复后会自动开始下载积压的补丁，可能多次重启）
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'SetDisableUXWUAccess' -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' | Where-Object State -eq Disabled | Enable-ScheduledTask
sc.exe config wuauserv start= demand ; sc.exe start wuauserv

# 放宽 UWP 后台应用（恢复邮件/日历同步、磁贴、UWP 通知）
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -ErrorAction SilentlyContinue
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 0 -Type DWord

# 搜索索引改回 Windows 默认
sc.exe config WSearch start= delayed-auto ; sc.exe start WSearch
```

> 实测：一台被"关闭更新"工具处理过的机器上，这三项都处于被关闭状态；恢复更新后系统会自行下载积压的补丁。

## 显卡稳定性（遇到游戏崩溃 / 黑屏 / TDR 再做）

`tune` 阶段只管「无效配置」，**不碰驱动稳定性**。真正遇到**游戏中崩溃、屏幕黑一下又恢复、进游戏那一刻挂掉**时，按这个顺序处理：

| 步骤 | 动作 | 依据 |
|---|---|---|
| **1. 先取证** | 看 `C:\Windows\LiveKernelReports\WATCHDOG\` 有无新增 `.dmp`；在应用程序日志搜 `LiveKernelEvent` | 区分「偶发」与「反复」，也排除掉「其实是游戏自己崩」的误判 |
| **2. 恢复设备** | `pnputil /restart-device "<InstanceId>"` | 实测几秒修好 `CM_PROB_FAILED_ADD`，**不用重启**（见 `reset-failed-devices.ps1`） |
| **3. 加大驱动超时** | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` → `TdrDelay=8`、`TdrDdiDelay=8`（默认 2 / 5 秒） | 驱动响应慢时不被看门狗直接判死。**需重启才被驱动读取** |
| **4. 关 AMD ULPS** | 显示适配器类键下 `EnableUlps=0` | ULPS 是 AMD「黑屏 / 驱动崩溃」的著名元凶。**吻合点是「空闲→满载」的切换，也就是进游戏那一刻**。代价：待机功耗略升 |
| **5. 散热 / 驱动重装** | 清灰换硅脂；DDU 安全模式清除后装厂商驱动 | 前四步都是软件层。迷你主机 / 笔记本在游戏满载下的问题往往在这里 |

三条纪律：

- **驱动版本不要盲目「更新」** —— Windows 更新推荐的显示驱动**可能比已装的更旧**。判断依据是**版本号第 3 段（分支构建号）**，不是「更新」二字。
  > ⚠ **只看第 3 段；第 4 段会反向误导。** 实测 `31.0.12027.9001` → `31.0.21925.1001`：第 3 段 `21925 > 12027` 判为**更新**，而**同一次比较里第 4 段 `1001 < 9001` 反而更小**。旧表述「比对第 3、4 段」按字面执行会得出相反结论。
  > ⚠ **Raven Ridge / Polaris 必须用 `-vega-polaris` 包**（`whql-amd-software-adrenalin-edition-<版本>-win11-may-vega-polaris.exe`）。主线 Adrenalin **已不含 `DEV_15DD`**，装错包会失败或回退。AMD 的 legacy 文档（GPU-630）里**没有** Vega/Raven Ridge，它们走的是独立的 Polaris & Vega 维护轨，不是停更。
  > 无故障体征时要不要升：`Windows Update` 驱动列表为 0 + 设备 `Status=OK` + 无 `LiveKernelReports\WATCHDOG` 转储 ⇒ 升级只是版本号上的前进，**收益不可量化**，属于"可做可不做"，别把它当修复。
- **一次只改一个变量**，每步之后进游戏实测，否则无法归因。
- **显卡挂掉会让游戏重跑硬件检测** —— 不支持 DPI 感知的游戏在检测不到原显卡时，会把画质/分辨率改回通用推荐值（实测被改成 1280×1024 + 画质中 + 抗锯齿开）。**游戏设置被改坏是这个故障的症状，不是原因**，别往游戏配置上排查。

## 唯一入口

```powershell
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1              # 全部阶段，按顺序
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase check # 只做前置检查
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase dev,apps
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase tune -WhatIf
```

| 阶段 | 做什么 | 需要管理员 |
|---|---|---|
| `check` | **前置检查 + 引导安装**：PowerShell 7 / Scoop / git / 7-Zip / 长路径 / 开发者模式 / 网络 / 磁盘 / 提权 / 系统版本（按 UBR 判断补丁级别） | 部分需要 |
| `dev` | Scoop 装语言与构建工具 + **VS Code / Windows Terminal** + 国内镜像（pip/npm/go/cargo/**HF**）；修 PATH、Store 存根、凭据助手 | 部分需要 |
| `apps` | 按 `apps.json` 装便携软件：下载 → **校验 SHA256** → 解压 → 折叠单层目录 → 快捷方式/PATH | 否 |
| `drivers` | 列出故障设备（含故障码）；查询 **Windows 更新里的驱动更新**（`-InstallDrivers` 安装）；厂商驱动缺失时给出检索路径（Microsoft Update Catalog + 装前校验 INF 硬件 ID） | 是 |
| `tune` | **先快照**，再应用：游戏调优（GameDVR/MMCSS）+ **关闭无效配置**（广告推荐/开始菜单联网搜索/遥测）；可选电源计划与鼠标加速 | 是 |
| `link` | 注册文件关联让 Windows 能选到这些程序；报告哪些类型还需手动点一次 | 否 |
| `verify` | 验收：开发环境 / 软件清单 / 输入法健康 / 服务基线漂移 | 否 |

配套工具箱（同一目录，可单独调用）：

```
snapshot-services.ps1     -OutDir <dir>               改动前拍照（只读）
compare-services.ps1      -Snapshot <csv> [-Restore] [-Only X]   对比 / 按基线回滚
diagnose-ime.ps1          [-Repair]                   输入法故障诊断（含 ctfmon 退出码、语言栏模式、IFEO）
reset-failed-devices.ps1  [-Reset] [-Class X]         设备故障码分诊与复位
install-portable.ps1      -Manifest <json>            清单式便携安装
check-software.ps1        [-Json]                     便携软件盘点（不进系统应用列表）
set-app-associations.ps1  [-Register -Apps @{}]       关联注册 / 现状报告
clean-orphan-associations.ps1 [-Clean]                卸载后的关联残留清理
audit-env.ps1 / fix-env.ps1 / setup-langs.ps1 / verify-env.ps1     开发环境四件套
```

## 三条纪律（违反就会被坑）

### 1. 绝不按"显示名"去禁用服务

**按需启动（Manual）的服务禁用后省不到任何性能，只会在某天爆发。** 实测代价表：

| 服务 | 显示名让你以为 | 禁掉的真实后果 |
|---|---|---|
| `TabletInputService` | 触屏键盘 | **中文输入法消失**、`Win+空格` 无反应、`ctfmon` 退出码 1 |
| `stisvc` | 图像采集 | 手机/相机/扫描仪**导不了照片** |
| `XboxGipSvc` | Xbox 配件 | **手柄**不工作 |
| `XblAuthManager` / `XblGameSave` / `XboxNetApiSvc` | Xbox | 商店游戏/Game Pass 登录、云存档、联机 |
| `WSearch` | 搜索索引 | 开始菜单/资源管理器搜文件不完整 |
| `Spooler` | 打印后台 | 打印全废 |

反过来：`RemoteRegistry` / `DiagTrack` / `SysMain` / `Fax` / `RetailDemo` 在很多机器上**出厂就是禁用**，
别把它们当成自己的"加固成果"，回滚时也别顺手打开。

### 2. 动系统前先拍快照

```powershell
pwsh -File scripts/snapshot-services.ps1 -OutDir C:\backup\before-tweak
```
没有基线就无法回答关键问题：*这个设置是我改的，还是本来就这样？*
`setup.ps1 -Phase tune` 会自动做这一步。快照目录含自启项导出，**属私有数据，不要提交公开仓库**。

### 3. 改完必须重启再验证

服务启动类型、网卡电源、输入法栈**都要重启才暴露问题**。真实案例：服务已经 `Running`，
`ctfmon` 仍然起不来、输入法仍然不能用；**重启后一切正常**。坏掉的登录会话不会自愈。

## 运行上下文矩阵（先问"谁在跑"，再判断结果）

> **同一个 Windows 上，"什么主机、什么权限、什么会话"决定了同一段代码的结果。**
> 本项目已经因为搞错这一层而误判过两次：一次是把「提权进程看不到非提权映射」当成映射失效，
> 一次是把「PS7 通过」当成脚本没问题（实际会被 5.1 拒绝）。**判断任何结果前，先定位它在矩阵里的哪一格。**

| 谁在运行 | 宿主 | 提权 | 会话/命名空间 | 由此产生的硬约束 |
|---|---|---|---|---|
| 你手动敲 `pwsh` | **PS 7** | 看窗口 | 交互会话 | 最宽松，**但不能代表其它格** |
| `setup.ps1` 及其子脚本 | **PS 7**（无 pwsh 时**静默降级** 5.1） | 通常提权 | 交互会话 | 日常运行**几乎不会走 5.1 分支** —— 5.1 的问题因此长期不暴露 |
| **计划任务** | **永远 5.1**（`powershell.exe`） | `RunLevel=Limited` = 非提权 | 用户会话，**独立于你的提权命名空间** | ① 脚本必须 ASCII-only 或带 BOM；② 参数栏不走 Shell，重定向无效；③ 工作目录是 `C:\Windows\System32` |
| 登录脚本 / 启动文件夹 | 取决于 `.lnk` 里写的是 `pwsh` 还是 `powershell.exe` | 非提权 | 用户会话 | 与 explorer 同级，能建出用户可见的驱动器映射 |
| explorer.exe | — | **非提权** | 用户会话 | **它只认非提权侧建的驱动器映射** |
| 提权 PowerShell | PS 7 或 5.1 | **提权** | 同一会话 Id，**但映射命名空间不同** | `Get-SmbMapping` 为空**不代表**用户没映射 |

**三条由矩阵直接推出的操作规则：**

1. **验收要在"目标格"里做** —— 验计划任务就得在计划任务里验（或起一个同权限的子进程），在提权窗口里验非提权行为一定误判。
2. **写完任何 `.ps1` 先跑 `check-script-hygiene.ps1`** —— 它把"两个宿主会不会分歧"变成一次秒级检查，不依赖你记得这个矩阵。
3. **`$LASTEXITCODE` 在进程内调用时不更新** —— 想拿子脚本成败，要么真起子进程，要么解析它自己输出的判定表。

## 陷阱速查（每条都实测过）

| 现象 | 真相 |
|---|---|
| 改了注册表里服务的 `Start`，`Start-Service` 仍失败 | SCM 有缓存，必须 `sc.exe config <名> start= demand`（**等号后有空格**）通知它 |
| 命令返回成功，设置却没生效 | 回读验证。例：`Disable-NetAdapterPowerManagement` 报成功但值没变 |
| `Win+空格` 按下去毫无反应 | 语言栏处于**旧版切换模式**（该模式下热键被禁用）：`Set-WinLanguageBarOption`（不带参数=现代模式） |
| PS7 里 `Get-WinUserLanguageList` 抛 marshalling 错误 | PS7 的已知问题，改用 `powershell.exe`（5.1） |
| Windows PowerShell 5.1 跑脚本中文乱码/语法错 | 脚本文件缺 **UTF-8 BOM** |
| 默认程序改不掉 | `UserChoice` 有 `Deny SetValue` + Hash 保护；官方 COM API 在 Win10 返回 `0x80070002` 且不生效。**只能手动点一次**，脚本能做的只是"让它出现在候选里" |
| 关联指向已删程序 | 卸载后必须跑 `clean-orphan-associations.ps1`；修法是**把 ProgID 重定向到幸存程序**，不是删键（删了 Windows 会重建并可能指到第三个程序） |
| `TrustedInstaller` 启动类型变过 | 是 **Windows 更新自己**切的（事件 7040 有记录），不是优化脚本 |
| 快照里某服务 `StartMode=Unknown` | 受保护服务读不到注册表，**不是被改了** |
| `Get-HotFix` 说系统停在 2023 | 它不列累积更新；用 `UBR` 判断真实补丁级别 |
| **`Get-AppxPackage` 报 `0x80131539`** | Appx 模块是 **5.1 专有**（依赖 .NET Framework 的 WinRT 互操作），**在 PowerShell 7 里整个模块加载失败**。加上 `-ErrorAction SilentlyContinue` 就会**静默返回空**，从而误判"这个 UWP 应用不存在/被优化脚本删了"。查 UWP 一律用 `powershell.exe`（5.1） |
| **提权进程启动不了 UWP 应用** | 管理员上下文里 `Start-Process ms-photos:` **静默失败**（进程根本起不来），极易误判"应用坏了"。绕过：`explorer.exe shell:appsFolder\<PackageFamilyName>!App` —— explorer 会在用户的非提权上下文里拉起应用。桌面快捷方式同理：TargetPath=`explorer.exe`，Arguments=`shell:appsFolder\...!App` |
| 脚本给 5.1 跑却写成无 BOM 的 UTF-8 | 中文会被读成乱码（表现为**路径莫名不以 .lnk 结尾**、字符串比较失败等）。要么存成 UTF-8 **BOM**，要么用 PowerShell 7 跑（PS7 默认按 UTF-8 读） || **WU 报"安装成功"但系统版本没变** | 实测：累积更新是 **SSU+LCU 合并包**，可以出现"服务栈那半装上了、LCU 那半回滚"的情况——**WU 历史与事件日志都记成功，但 `UBR` 不变、更新又被重新提供**。判据只有一个：`CurrentBuild.UBR` 是否上升，别信"安装成功"。修法：SSU 落地后**重启再重试一次 LCU**（服务栈到位后通常就能提交）；仍失败则用 `dism /online /add-package` 装离线 msu（错误码可见，不再静默回滚） |
| 组件库检查 | `dism /online /cleanup-image /checkhealth` 是**秒级**的（`/scanhealth` 才慢）；报 `CBS_E_INVALID_PACKAGE` 的旧 KB（如 KB3025096）通常是陈年孤儿包，未必影响新更新 |
| 某设备显示 Error / Code 43 | **与优化无关，是缺厂商驱动**。`reset-failed-devices.ps1 -Reset` 只能清状态（实测 Code 43 蓝牙约 40 秒后复发）。**实测解法**：装厂商/UWD 驱动 —— 微软通用驱动加载不了设备固件（MT7921 蓝牙就是这样：通用驱动 → "适配器命令超时" → Code 43；装上 MediaTek UWD 驱动（含 7MB 固件）后整套蓝牙协议栈立刻 OK）。找不到驱动时用 **Microsoft Update Catalog** 检索，**装前必须确认 INF 里含你的硬件 ID**（如 `USB\VID_0489&PID_E0CD&MI_00`） |
| 开机日志 `7026 ... dam` / `DCOM 10016` | 良性噪音，不用管 |
| CPU 显示 100% | 用增量采样，别信 `LoadPercentage` 瞬时值 |
| 用 `-File` 调用脚本时 `-Only A,B` 只收到一个元素 | **`-File` 模式不拆逗号数组**（`-Command` 会拆）。要么脚本内部自己 `-split ','`，要么改用 `&` 在进程内调用传数组 |
| 遍历 `HKCU\Software\Classes` 慢到几分钟 | PowerShell 逐键读实测 **281 秒**；改用原生 `reg query /s` 全量 dump 后内存过滤约 **18 秒**。注意 `/f` **不能跨反斜杠匹配键名**（`shell\open\command` 要 `/s` dump 后自己过滤） |
| **累积更新会悄悄重置你的系统优化** | 实测**两次**：装完累积更新后，之前禁用的服务**全部回到出厂启动类型**，广告 / 推荐 / `GlobalUserDisabled` / `SystemResponsiveness` 等一批注册表值**直接消失**。**关键规律：它对这类设置是「删除值」而不是「改成别的值」——所以判断是否被重置必须看值存不存在，只看它等不等于期望值，会把「被删了」误判成「本来就没设置过」。** 判据：隔一次累积更新就重跑 `verify-env.ps1`（已内置 tune 存活检查，缺失值记为 FAIL）。**⚠ 先排除更简单的原因**：向同一个键写多个值时如果用了 `New-Item -Force`，只会剩下最后一个（见下方的受控实验）——**症状与「被累积更新重置」完全一样**，别一上来就归因于累积更新 |
| **`SystemResponsiveness` 写进去了但服务没跑** | 配置写对 ≠ 生效。`MMCSS` 是**内核驱动**，可处于 `START_TYPE=2 AUTO_START` 却 `STATE=STOPPED`、`WIN32_EXIT_CODE=1341 (ERROR_SERVICE_NOT_IN_EXE)`，此时 `SystemResponsiveness` 与 `Games` 优先级全部无效。修法：`sc.exe config MMCSS start= auto` 后用 `sc.exe start MMCSS` 拉起；验证要 `sc query MMCSS` 看到 `RUNNING`，**不能只看注册表值** |
| PS7 里 `Enable-ComputerRestore` / `Checkpoint-Computer` 找不到 | 与 `Get-WinUserLanguageList` 同理，**这两个 cmdlet 是 5.1 专有**。系统还原相关一律走 `powershell.exe`（5.1）。另外 `SystemRestorePointCreationFrequency` 默认限制 24 小时只能建一个还原点，脚本里先置 `0` |
| **系统还原点默认可能是 0 个** | 不少机器出厂就没开系统保护，等于没有任何回滚兜底。优化前建议先 `Enable-ComputerRestore -Drive 'C:\'` + `Checkpoint-Computer` 建一个基线 |
| **`bcdedit` 非提权执行「静默返回空」** | 不报错、也不提示「拒绝访问」，就是什么都没有——极易误判成「这个设置被清空了」。**实际提权后读写完全正常。** 这是同一类坑的第 N 个：`Test-Path` 把 `*` 当通配符、`Get-AppxPackage` 在 PS7 里模块加载失败、`Get-ComputerRestorePoint` 是 5.1 专有、WMI 的 `CurrentHorizontalResolution` 有缓存滞后。**通用教训：「查不到」不等于「不存在」，先确认查询手段本身有效** |
| **`foreach` 遍历哈希表不会枚举条目** | `foreach ($kv in $hashtable)` 得到的是**哈希表本身**（只迭代 1 次），`$kv.Key` 为 `null`，脚本以「无法将自变量绑定到参数 Name」这类莫名错误失败。`[ordered]@{}` 同样中招。**必须用 `$h.GetEnumerator()`**；而管道 `$h \| ForEach-Object` 反而会正常枚举——两种写法行为不一致正是坑点。实测同一场排查里连栽三次 |
| **显示设备的「名字」会变** | `pnputil /restart-device` 重新添加适配器后，Windows 会把活动显示设备从 `\\.\DISPLAY1` 改名成 `\\.\DISPLAY2`。**硬编码设备名的脚本会静默失效**：`EnumDisplaySettings` 对不存在的设备返回空，脚本却报「驱动不支持该分辨率」，完全误导。正确做法是枚举 `EnumDisplayDevices`，取 `StateFlags` 含 `0x1`（已连接桌面）的那个，优先 `0x4`（主显示器） |
| **`CM_PROB_FAILED_ADD` (Code 31) 不必重启就能修** | 现象：设备 `Status=Error`、取不到分辨率、3D 应用崩溃。**先试 `pnputil /restart-device "<InstanceId>"`** —— 实测几秒恢复，既不用重启也不用重装驱动。`reset-failed-devices.ps1` 已把它作为第一步，disable/enable 降为兜底 |
| **GPU 挂起的历史证据在 `LiveKernelReports`** | `C:\Windows\LiveKernelReports\WATCHDOG\*.dmp` 是**内核级看门狗转储**；配合应用程序日志里 `Windows Error Reporting → LiveKernelEvent`（`P1` 是事件码）能还原「什么时候挂过、挂了几次」。**设备恢复后这些记录仍在**，是判断「偶发还是反复」的唯一依据 |
| **别信文件夹名，看文件属性** | `C:\Program Files\AMD\Performance Profile Client\AUEPMaster.exe` 看着像性能配置组件，**实际 FileDescription 是 "AMD User Experience Program Master"（纯遥测）**。按文件夹名判断组件用途会做出错误的保留/禁用决策——实测差点为此把 77~90 秒的开机延迟白拿回来。**查 `(Get-Item x.exe).VersionInfo` 的 FileDescription / ProductName** |
| **scoop 一个坏清单会中止整批** | `scoop install python node go` 里只要有一个清单名在桶里不存在（`node` → 实为 `nodejs`，`dotnet` → 实为 `dotnet-sdk`），**整批立即中止**，后面的包一个都不装，而外层脚本照样往下走。**实测代价：整套语言链全部没装上，却一路报"成功"。** 判据：逐个回读 `~\scoop\apps\<名字>\current` 是否存在，别信退出码（`setup.ps1` 已改为逐个安装 + 逐个回读） |
| **`7zr.exe` 不认 ZIP** | `7zr.exe` 是 7-Zip 的**精简版**，**没有 ZIP 编解码器**，解 `.zip` 返回 exit 2。实测：唯一的 `.7z` 应用装好，三个 `.zip` 应用全挂。**ZIP 根本不需要外部工具**——用 in-box 的 `[IO.Compression.ZipFile]`（大包比 `Expand-Archive` 快得多）/ `Expand-Archive`；只有 `.7z` 才需要 7-Zip |
| **清单里的 exe 是相对路径，消费方不能用 `Split-Path -Leaf`** | 包里有多个顶层目录时"单层目录折叠"不会触发（JPEGView 有 `JPEGView32` / `JPEGView32-WinXP` / `JPEGView64` **三个**），清单必须写 `JPEGView64\JPEGView.exe`。**消费方若用 `Split-Path -Leaf` 取叶子名，子目录会被丢掉**，生成的快捷方式/关联指向不存在的文件；更稳的做法是直接用 `Join-Path` 拼清单里的相对路径再判存在 |
| **单一安装路径就是单点故障 —— 尤其当这个路径本身没被验证过** | 7-Zip 与 git 曾只由 `Scoop-Install @('git','7zip')` 负责。实测那台机器 **scoop 根本没装上**，于是 7-Zip 从未安装，而 `check` 阶段仍把整个 bundle 记作已处理 —— 用户最后自己去 7-zip.org 手动装的。**根因不是 scoop 坏了，而是"一个工具只有一个来源，且那个来源自己没被回读"**。修法：压缩工具改为 `apps.json` 的 `source: winget` 条目（与 scoop 解耦），`check` 先试 scoop、失败回落 winget，最后 `Test-ArchiveTool` 按**安装路径**回读；`verify` 里给 7-Zip / WinRAR 各一行独立检查。**判据：任何"必需工具"都要有 ≥2 条独立安装路径，且验收只认回读结果** |
| **"安装成功"的判据必须回读，且必须覆盖清单里的【每一个】条目** | 第一版只给新加的 winget 条目加了 `verifyPath` 回读，便携条目仍然"解压完就报成功" —— 于是 `exe` 写错时只 `WARN` 一句"跳过快捷方式"，安装结果照样算数（这正是 JPEGView 那个坑的真实成因）。**判据：给清单加一种新类型时，回读逻辑要抽象成公共函数并让所有类型走同一条路**（现在 `Resolve-InstalledPath` 同时服务 `verifyPath`(winget) 与 `exe`(便携)），汇总里报 **`verified N/M`** 而不是"无失败"。反向测试三条：目录在但 exe 被删 / `exe` 路径写错 / `-WhatIf` 下不得声称已安装 —— 三者都必须 FAIL |
| **盘点只认一个目录 = 把正常安装误报成缺失** | `check-software.ps1` 早年靠"扫 `~\Apps\` + 猜主 exe"盘点。加上清单回读后立刻暴露问题：**Notepad++ 与 TrafficMonitor 在真实机器上是 winget 装的**（在 `Program Files` / `WinGet\Packages`），只查便携目录会报 `MISS` —— 把正确的安装说成缺失。修法是清单里加 `altPaths`（支持通配符），输出标注来源 `[portable]` / `[vendor]` / `[alt]`。**判据：判"缺失"之前先确认"它本该在几个地方"** |
| **写检查项的人必须和写实现的人对齐** | `verify-env.ps1` 检查 `Tasks\Games\GPU Priority` / `Scheduling Category`，而 `tune` 阶段原先**从不写它们** ⇒ 这两项在**任何机器上都必然 FAIL**。长期挂着的假失败会把真问题淹没 |
| **声明的镜像 ≠ 实际生效的镜像** | 每个镜像配置都被 `if (Get-Command <tool>)` 守卫，工具链没装成功就整段跳过——而汇总行仍**硬编码打印"镜像已生效"**。实测：nodejs 下载失败 ⇒ npm 镜像根本没设，汇总却报 `npm=registry.npmmirror.com`。**汇总必须逐项回读**（`npm config get registry`、`pip config get`、`go env GOPROXY`），不能打印期望值 |
| **`CARGO_HOME` 不一定是 `~\.cargo`** | scoop 的 `rustup` 包把 `CARGO_HOME`/`RUSTUP_HOME` 指向 `scoop\persist\rustup\`。往 `~\.cargo\config.toml` 写镜像会被**静默忽略**；同理在 `RUSTUP_HOME` 未生效的进程里 `cargo` 会报 "no default toolchain"。**写配置和查状态前都要先解析 `$env:CARGO_HOME` / `$env:RUSTUP_HOME`** |
| **装载期内核驱动（MMCSS）会失败很多次，但别据此断言"拉不起来"** | 实测（另一台机器）：装显卡驱动把 `MMCSS` 带停。随后连续多次启动都失败，错误码还会**变**：先是 `失败 2: 系统找不到指定的文件`（而 `mmcss.sys` 完整存在、53248 字节、签名有效），**重启后仍失败**并变成 `1341（服务器当前已禁用）`。**但它最终确实起来了** —— `sc.exe config MMCSS start= auto` + `sc.exe start MMCSS` 在约 40 分钟后成功，`sc query` 显示 `RUNNING`、`WIN32_EXIT_CODE=0`，间隔 15 秒复检仍稳定。**结论：正确动作是"重试/重启"，不是"判定它坏了"**；排查配置层面（文件/签名/服务键/IFEO/代码完整性）通常全部正常，那不代表它不会恢复。**判据：`sc query MMCSS` 必须看到 `RUNNING`**——服务停时 `SystemResponsiveness` 与 `Games\*` **全部无效**，只看注册表会漏掉"值在、服务停" |
| **1341 对内核驱动而言是「本次没加载」，不是「配置错了」——重启即可** | 实测一台 Windows 11 机器：`MMCSS` 的 `Start=0x2`(引导期 AUTO_START)、`Type=0x1`、`ErrorControl=0x1` 全部正确，驱动文件在位（90,112 字节、10.0.26100.8972、签名有效），事件日志却是 `7000 由于下列错误，MMCSS 服务启动失败: 服务器当前已禁用`，且 `sc start MMCSS` **当场失败返回 1341**。**重启后直接 `STATE: 4 RUNNING`、`WIN32_EXIT_CODE 0`**，无需 `sc config`、无需多次重试。**判据：配置项全对 + 启动失败 ⇒ 先重启再下结论**；引导期驱动在运行中途起不来是**预期行为**，不是故障。（与上一条"重试 40 分钟才起来"不矛盾：上一条是在**同一次开机内**反复 `sc start`，重启才是正确处置。） |
| **有些键的 ACL 看着是全权，写入却被内核层拒绝** | 实测 Windows 11 24H2+：`HKCU\Software\Microsoft\Windows\CurrentVersion\Search` 的 ACL 明确列出当前用户 `FullControl`、`Owner` 也是该用户、进程已提权，但 `reg add` / `New-ItemProperty` / `reg import` **全部**返回 `拒绝访问`（`reg import` 原文：`Not all data was successfully written to the registry`）。**这不是 ACL 问题**——同一批写入里其它键（如 `...\Explorer\Advanced`）全部成功，也**没有第三方安全软件介入的证据**（查过其日志）。**别去夺取所有权或改 ACL**（既无用又危险），改走**官方策略路径**：开始菜单联网搜索用 `HKCU\Software\Policies\Microsoft\Windows\Explorer` 的 `DisableSearchBoxSuggestions=1` + `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` 的 `ConnectedSearchUseWeb=0` / `AllowCortana=0`。策略**优先级高于**用户作用域，"换路径"不是降级。**判据：写入失败先分辨是不是"ACL 正常却被拒"，是就别硬碰，找策略键** |
| **`reg import` 是部分写入：一个键被拒会跳过它后面的所有节** | 实测：`.reg` 里含一个写不进去的键时，`reg import` 返回 **exit 1**，**已写成功的键保留**，**其余尚未处理的节全部跳过**。真正的危害是**归因被带偏**：回读会报"后面 N 个值 not present after the write"，看起来像 N 个互不相关的失败，真凶却是中间那一个被锁的键。**纪律：不要把"可写性未知的键"放在批量导入的中间**；不确定的键单独成批，或（更好）直接换官方策略键 |
| **「状态不等于我预期的值」≠「坏了」——优化审计里最容易冤枉系统的三类** | 同一场审计里连栽三次，全是判定标准写窄、把**正常行为**判成故障：① 快捷方式 `IconLocation` 为空路径 + 索引（`,0`）被读成"图标缺失"，实际那是 Windows 表示"沿用目标程序自带图标"的**正常写法**（本机 31 个快捷方式里 15 个都这样）；② 计划任务 `Disabled` 被读成"被回滚"，实际 `DiskDiagnosticResolver` / `OOBEFodSetup` 这类**一次性任务运行成功后自我禁用是设计**（判据是"本次已跑且 `LastTaskResult=0x0`"，不是"当前是否 Ready"）；③ 电源方案"最小处理器状态 = 80%"被读成"比高性能还激进的待优化项"，实际可能是**厂商为响应手感有意设的地板**（实测降到 10% 后用户反馈"响应变肉了"，回退 80% 才恢复）。**通用纪律：报 FAIL 之前先问一句"这个值有没有可能本来就是对的？"**，尤其当形态是"空值 / 禁用 / 偏离默认"时 |
| **显示设备名在驱动重装后会改** | 实测**两次**：装驱动 / `pnputil /restart-device` 之后 `\\.\DISPLAY3` → `\\.\DISPLAY1`，硬编码设备名的脚本**静默失效**。而且 `ChangeDisplaySettingsEx(NULL, ...)` 在 Win10 返回 **`DISP_CHANGE_BADPARAM(-5)`**，必须显式传设备名；`EnumDisplaySettings` 也要传同一名字。**取名字用 `[Windows.Forms.Screen]::AllScreens` 里 `Primary` 那个**——实测 `EnumDisplayDevices` 的 P/Invoke 在本机**一直返回 false**（`SizeOf=840` 结构体大小是对的，仍失败） |
| **`Get-ComputerRestorePoint` 非提权返回空** | 同一个 cmdlet：**非提权枚举返回 0 个还原点，提权后能看到 3 个**。据此会误判"这台机器没有任何回滚兜底"。**又一条"查不到 ≠ 不存在"**——系统还原相关一律在提权上下文里查（`Enable-ComputerRestore` / `Checkpoint-Computer` 本身也是 5.1 专有） |
| **`New-Item <键> -Force` 会清空整个键 —— 这才是「调优值神秘消失」的真凶，不是杀软** | `New-Item <键> -Force` 对**已存在**的注册表键是**重建**，会把键里已有值全部删掉。受控实验（同一探针键）：`4×(New-Item -Force + Set-ItemProperty)` 只剩 **1** 个值；`4×(仅 Set-ItemProperty)` 保留 **5** 个值。而 tune 循环**每写一个值前都调一次 `New-Item -Force`**，于是向同一个键写 N 个值**只有最后一个能活**——却照样报 `applied N registry change(s), 0 failed`。**本机实测对照：旧写法 18 项事后只剩 4~8 项；改成「仅当键不存在时才创建」后 30/30 全部落地、20 秒后仍 30/30 存在。** 判据：向同一个键写多个值时**绝不**用 `-Force` 建键；验证要**按键逐值**回读，别只看汇总计数。⚠ 曾据此**误判**为「安全软件在回滚注册表」——错的，那台机器上根本没有回滚代理 |
| **`-Verb RunAs` 不能配输出重定向** | `Start-Process -Verb RunAs -RedirectStandardOutput ...` 直接报"无法使用指定的命名参数解析参数集"，**UAC 根本不会弹**（容易误判成"用户拒绝了"）。提权脚本要留日志只能在脚本里用 `Start-Transcript` |
| **PowerShell 变量名不区分大小写** | 局部变量 `$test` 会和参数 `[switch]$Test` **冲突**：赋值报 `Cannot convert ... to SwitchParameter`，**错误信息完全不提参数名**。与 `setup.ps1` 里"参数不能叫 `$Args`"是同一族坑 |
| **大文件下载用 `curl -C -` 续传，SHA256 做裁决** | 网络抖动会中断 `Invoke-WebRequest`（**它不支持续传**），重下 600 MB 代价很高。`curl.exe -L -C -` 断点续传后**必须核对 SHA256**——校验通过才证明续传文件字节级正确（实测 653,644,328 字节精确匹配、哈希一致） |
| **`Test-Connection` 是 ICMP，会假阴性** | `-Phase check` 报 `github.com not reachable`，而同一条网络上 `Test-NetConnection -Port 443` 通畅、仓库照下不误。**ICMP 被挡是常态**——判断网络用 TCP 443，别用 ping |
| **便携软件的"省电"设置会让游戏掉线** | 网卡默认**允许系统关闭以省电**，表现为**游戏中随机掉线 / 延迟尖峰**。正解是官方注册表项 `PnPCapabilities = 24 (0x18)`（网卡类键下），**而 `Disable-NetAdapterPowerManagement` 会返回成功却不改值**（见 `docs/system-tweaks-audit.md`）。生效需**重启网卡或系统**。实测出厂值：有线网卡未设置、无线网卡 `16`，两者都应为 **24** |
| **无 BOM 的中文脚本在 PS 5.1 下会解析失败，而 PS 7 下正常** | 实测：`verify-env.ps1` 含 27 个非 ASCII 字节、**无 BOM**。用 `pwsh`(PS7) 跑完全正常；用 `powershell.exe`(5.1) 跑**直接在 here-string 处解析失败**（报 `The '<' operator is reserved for future use`，因为它把内嵌的 C++ 当 PowerShell 解析）——5.1 按 ANSI 解码 UTF-8 字节，错位后可能吐出引号，把 here-string 提前截断。**这条之所以长期没暴露：`setup.ps1` 调子脚本用的是 `pwsh`。** 纪律：脚本**要么纯 ASCII**（本目录所有脚本都声明 ASCII-only），**要么存成 UTF-8 BOM**。需要中文字面量时用 `\uXXXX` 转义（.NET 正则和 Python 都认），保持文件纯 ASCII。**⚠ 这条写进文档后仍然又发生过一次**（写一个给计划任务调用的 wrapper），详见下方「语法校验通过 ≠ 脚本能跑」与 `check-script-hygiene.ps1` |
| **语法校验通过 ≠ 脚本能跑** | `[Parser]::ParseFile` 读无 BOM 文件时按 **UTF-8** 解码，而 `powershell.exe -File` 按 **ANSI** 解码——**同一个文件，前者报 ok、后者报解析错误**（上面那条就是这么漏掉的）。**判据改成了工具**：`check-script-hygiene.ps1` 对目录下每个 `.ps1` 做**双宿主解析 + 编码检查**（不执行，秒级），已挂进 `verify-env.ps1`。**为什么必须机械化**：这条纪律靠"记得做"已经被证伪两次 —— 同一个坑先让 `verify-env.ps1` 自己栽过，后来又让一个给计划任务写的 wrapper 栽过（PS7 过、5.1 报 `The string is missing the terminator: '`）。**判据：写完任何 `.ps1` 就跑一次 hygiene 检查，别靠记忆** |
| **计划任务的「参数」栏不通过 Shell 执行 —— 重定向语法静默失效** | 在任务的参数里写 `cmd /c "... > log 2>&1"`，**重定向不会执行**，日志文件根本不生成，而任务照样报「成功」。**日志必须由脚本自己写**（`Add-Content` / `[IO.File]::WriteAllText`）。同理，任务里的相对路径不可靠——实测任务的工作目录是 `C:\Windows\System32`，一切路径都要写全 |
| **计划任务报 `0x1` 时，`LastTaskResult` 是唯一的证据 —— 历史记录可能全部显示「成功」** | 实测一次真实事故：任务历史依次是 `100 已启动` → `110 已为用户启动` → `129 启动进程 PID` → `200 操作已启动` → **`201 操作成功完成`** → **`102 任务成功完成`**，而 `Get-ScheduledTaskInfo.LastTaskResult` 是 **`0x1`**。进程确实起来了、1 秒后退出、什么都没做。**排查前提：`TaskScheduler/Operational` 日志默认禁用**，不先 `wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /e:true` 就只能靠猜 |
| **`$LASTEXITCODE` 不会被「进程内调用脚本」设置 —— 会拿到上一个子进程的陈旧值** | `& .\child.ps1` 在当前会话内执行，**`$LASTEXITCODE` 保持之前的值不变**。实测后果：一个本该 FAIL 的校验被读成 PASS（更早的某次子进程调用留下了 0）。**拿子脚本退出码只有两条路**：真的起子进程（`& powershell.exe -File child.ps1`），或者**解析脚本自己输出的判定表、别信退出码** —— 判断成败时至少用其中一条，不能只看 `$LASTEXITCODE` |
| **驱动器映射按「登录会话 + 提权级别」隔离 —— 提权进程看不到非提权的映射** | 实测同一台机器、同为 SessionId 3：**提权** PowerShell 里 `Test-Path 'Z:\'` = False、`Get-SmbMapping` 为空，而**非提权**的计划任务里同一个 `Z:` = True 且 `Status=OK`。**这不是故障，是设计**：UAC 分裂出的两个令牌各有独立的映射命名空间。**推论**：① 验收"映射是否可用"必须在**非提权**上下文做（explorer 也在非提权侧），否则会把正常隔离误读成失效；② 计划任务要用 `RunLevel=Limited`，映射才会建到 explorer 能看到的那一侧 |
| **驱动器映射不会在睡眠/唤醒后自动恢复** | 实测：近 3 天睡眠 4 次 / 唤醒 4 次，**每次唤醒后 `Z:` 都消失**（`Get-SmbMapping` 为空）。原因**不是网络** —— 47 次「网卡断开」事件与睡眠时刻**精确对齐到同一秒**，链路本身健康；而是**没有任何东西在唤醒后重连**（启动脚本只在登录时跑一次）。持久映射记录（`HKCU\Network\Z:`）与凭据都在，手动重连 1 秒成功。**修法**：加事件触发的计划任务，订阅 `Microsoft-Windows-NetworkProfile/Operational` 的 **EventID 10000（网络已连接）**，实测每次唤醒后都会触发 |
| **`-WhatIf` 遇到前置依赖缺失就硬退出 —— 于是新机器上根本没法预览** | `setup-langs.ps1` 的 `Step '0. Preconditions'` 在 scoop 缺失时 `exit 1`，而 **`setup.ps1 -Phase check` 才是装 scoop 的那一步**。结果：一台干净机器上 `setup-langs.ps1 -WhatIf` 在打印任何计划动作**之前**就退出了 —— dry-run 恰恰是为新机器准备的。**判据：预览模式必须能走完全程并列出"将会做什么"，即使依赖尚未就位**（真跑时该失败仍然失败）。同理，读注册表/服务状态之外的**计划动作**要用 `would ...` 明确写出来，不能因为前置缺失就整段跳过 |
| **`ForEach-Object -Parallel` 的两个硬限制** | ① **`$using:` 只能引用变量本身** —— 不接受索引、不接受表达式：`$using:map[$k]` 和 `$using:f($k)` 都报 `Using 表达式中不允许使用表达式`。正确写法是把**整张表**带进去（`$m = $using:map`）再在块内索引。② **打印顺序会随线程完成顺序漂移**，所以 `Write-Output` 不能在并行块里直接调 —— 要先把结果收成对象数组，循环**结束后**再按固定顺序输出，否则报告无法 diff。另外 `-Parallel` 是 PS7 独有，5.1 必须保留顺序分支（实测两条路径输出一致：20 项探测 2.11s → 0.61s，逐条差异 0） |
| **`| Out-Null` 加上"不参与 Record"，等于把失败静默吞掉** | `setup.ps1` 的 verify 阶段曾这样写：`Invoke-Step 'compare-services.ps1' @(...) 'service baseline drift' \| Out-Null`，而 `Record 'verify' ($a -and $b -and $c)` **没有包含它**。叠加后果：`compare-services.ps1` 对**缺失的快照**会 `exit 1`（实测 `FAIL snapshot not found`），但那个失败既不出现在阶段结果表、也不影响退出码 —— 于是**单独跑 `verify` 的机器（还没跑过 `tune`，因而没有快照）会静默丢失整项检查，而用户看到的是 `verify PASS`**。**判据：凡是"结果会决定成败"的调用，返回值必须同时进入 ① 可见输出 ② 退出码；`Out-Null` 只能用于真正无关紧要的调用。** 另外，缺前置数据时要**显式跳过并说明**，不要走进一个必然失败的调用 |
| **机器代码完整性策略会让「5.1 回退路径」整体失效** | 实测一台机器：`Windows PowerShell 5.1` **拒绝执行该目录全部 14 个脚本**（`cannot be loaded ... not digitally signed`），`pwsh` (PS7) 则 14/14 正常。受控实验定位到原因是**路径 + WDAC**：Desktop 下任意子目录都被拒，用户 TEMP / 用户主目录正常；该机有 8 个 WDAC 策略文件且 `CodeIntegrityPolicyEnforcementStatus = 2`（强制）。**这不是脚本缺陷**（脚本无 Zone 标记、无签名要求），但**推论很重要**：`setup.ps1` 在没有 `pwsh` 时会静默降级到 5.1，在强策略机器上那一刻**全部子脚本都会失败**，而 `check` 阶段可能已经报过成功。**所以"装 PowerShell 7"不是体验优化，而是硬前提** |
| **脚本只打印 `failures (N)` 却不设退出码 —— 调用方读到的永远是成功** | `setup-langs.ps1` 原本**没有任何 `exit` 语句**，所以 `$LASTEXITCODE` 不反映结果。而 `setup.ps1` 的 `Invoke-Step` **正是用 `$LASTEXITCODE -eq 0` 判定这一步成败** ⇒ 一个装挂了的工具链会被判为通过。**判据：凡是被 `Invoke-Step` 调用的脚本，结尾必须显式 `exit 0/exit 1`** |
| **`reg query /s` 的行解析会把非默认值当成默认值** | 解析 `...\shell\open\command` 时用 `'REG_SZ\s+(.*)$'` **不检查值名**，于是 UWP 的 `DelegateExecute REG_SZ {GUID}` 被读成了命令行（本机 268 条里 85 条是这种形状）。**改用 .NET `RegistryKey.GetValue('')` 读真正的默认值**：顺带把 4.1 秒降到 0.4 秒。**两个伴生陷阱**：① 该 hive 里 **`Shell` 与 `shell` 大小写混用**，大小写敏感的比较会静默丢条目（`-match` 默认不敏感才没暴露）；② 只看一层（`Classes\<ProgID>\shell\open\command`）会漏掉全部 `Classes\Applications\<exe>\...`（本机 90 条）—— 那看起来是 138× 提速，实际只是**算少了** |
| **写代码的 Agent 自己会违反 ASCII-only 纪律 —— 而且是在刚读完这条纪律之后** | **实测已被触发 4 次**：① `verify-env.ps1` 自己（27 个非 ASCII 字节）② 一个给计划任务写的 wrapper ③ 给 `setup-langs.ps1` / `install-portable.ps1` 补注释时写中文章节名 ④ 给 `install-portable.ps1` 补注释时写了 `条件安装` 四个字（4×3=**12 字节**，与检查器报出的数字完全吻合）。**四次的共同点：都是在"写注释"时发生**，而且都是在**刚讨论过这条纪律之后**。**结论不是"要更小心"，而是：把检查放进流程** —— 改完该目录任何 `.ps1`，先跑 `check-script-hygiene.ps1` 再提交，它会把这类错误在提交前挡下来（本次四次里有三次就是被它挡下的）。**混写风险最高的场景**：文档是中文、脚本是 ASCII-only，**脚本注释里引用文档时只写章节编号，不要抄中文标题**；要表达中文概念就改用英文描述 |
| **`-WhatIf` 不会自动传给子进程 —— "预演"因此可能真的在装软件** | `setup.ps1` 用 `& $pwshExe -NoProfile -File $child @Arguments` 调子脚本，而 **11 个调用点没有任何一处把 `-WhatIf` 放进 `@Arguments`**（实测核对）。于是 `setup.ps1 -Phase dev -WhatIf` **真的去装工具链**、`-Phase apps -WhatIf` **真的下载并安装软件**、`-Phase link -WhatIf` **真的写关联注册**，而横幅还印着 `WhatIf: nothing will be changed`。**判据：`-WhatIf` 是进程级偏好，不出本进程；每个跨进程调用都要自己转发**。转发时**不能无脑加** —— 不支持 `SupportsShouldProcess` 的子脚本会因为多出 `-WhatIf` 参数而绑定失败（本目录 14 个里有 3 个不支持）。做法：读子脚本源码判断它是否声明 `SupportsShouldProcess`，只对声明了的转发 |
| **`Set-Content` 自己支持 `-WhatIf` —— 会造出"文件不存在"的假故障** | `-Phase tune -WhatIf` 曾稳定打印 `FAIL reg import: ERROR: Error opening the file`。链条是：`ShouldProcess` 在 `-WhatIf` 下全部返回 false → 待写清单为空 → **`Set-Content` 也遵守 `-WhatIf`，临时 `.reg` 文件根本没被创建** → 但紧接着的 `reg.exe import` 不受影响，去导入一个不存在的文件。**同一个问题的第二面**：汇总行报 `applied 0 registry change(s)`，读起来像"没事可做"，而真相是"23 项会改"。**判据：`-WhatIf` 分支要自己算"将会改多少"并说出来**（现在输出 `WhatIf: 23 registry value(s) across 10 key(s) would be set`），且**预演路径里不许再调外部写入工具** |
| **"清单里声明了" ≠ "必须装"：4 个 Electron 编辑器装完又全卸** | 清单原本声明 MarkText（Electron + 实时预览）。实测把 **MarkText / VNote / Yank Note / Zettlr 四个都装过**，最终**全部卸载**，换成**原生 Notepad++**。原因是一致的：Electron 编辑器是这个清单里**启动最慢**的一类，而用户的真实诉求是"启动快、界面简单"。**判据：清单是"候选集"，不是"必装集"** —— 遇到"简单快速"这类诉求时，先问一句再装；**实时预览不需要新装应用**（已装的 VS Code `Ctrl+Shift+V` 就够）。现在 `apps.json` 已改为 Notepad++（portable 包自带 `doLocalConf.xml`，配置留在程序目录），MarkText 条目删除 |
| **别的程序的 ini 靠 BOM 判编码 —— 用 `-Encoding Default` 改它必然乱码** | 给 TrafficMonitor 改 `config.ini` 时用了 `Set-Content -Encoding Default`。PowerShell 7 的 `Default` 写**无 BOM** 的 UTF-8，而 TrafficMonitor **靠 BOM 判断编码**，没有 BOM 就按系统 GBK(936) 解码 ⇒ `内存` 变成 `鍐呭瓨`、`↑` 变成 `鈫?`，用户看到的就是"字体混乱"。**注意这跟本项目那条"脚本必须 ASCII-only"是同一个编码家族、方向相反**：那边是**我方脚本被 PS 5.1 当 ANSI 读**，这边是**别人的程序配置被我写成无 BOM**。**判据：改第三方程序的配置文件前，先看它原来的 BOM 再原样保持** —— 用 `[System.Text.UTF8Encoding]::new($true)` 显式带 BOM 写，改完回读中文串确认没有 `鍐/鈫/閸` 之类乱码 |
| **"读 → 写" 会累积 BOM，而且没有任何报错** | 用 `GetString([IO.File]::ReadAllBytes(p))` 读一个带 BOM 的文件时，BOM 会变成字符串里的 `U+FEFF` 留在开头；再用 `UTF8Encoding($true)` 写回，就会**再补一个 BOM**。实测同一个文件被读了写两次之后变成 **3 个 BOM**（`EF BB BF` ×3），首行从 `[general]` 变成 `\uFEFF\uFEFF\uFEFF[general]` —— 于是按行首锚定的 `^\[general\]` 正则**静默匹配失败**，配置改了却像没改；这个缺陷同时污染过本机配置和已提交的 `presets/TrafficMonitor.config.ini`。**判据：写回前先 `$t = $t.TrimStart([char]0xFEFF)`，或者"字符串已含 BOM 就用 `UTF8Encoding($false)`"**；改完必须数一下前 3 字节，只允许一组 `EF BB BF` |
| **诊断脚本的"服务不存在"分支容易漏掉状态标志** | `diagnose-ime.ps1` 只在"服务被禁用"时置 `$badService=$true`，**"服务缺失"分支只打印 FAIL 不置标志** ⇒ 第 1 段报 FAIL、第 6 段却判 `The IME stack looks healthy`，且 `-Repair` 走到 `not disabled - nothing to repair here` 什么也不做。**判据：每个失败分支都必须落到同一个判定变量上**，且"缺失"与"被禁用"是两种不同的失败模式（`sc config` 无法创建不存在的服务，要改走 `sfc` / `DISM`） |
| **脚本注释里指向文档的引用会随文档重构而失效** | 文档重排章节后，`setup-langs.ps1` 仍写 `see the README for the bootstrap step`、`install-portable.ps1` 仍写 `See README "Manifest format"` —— 两个章节名都已不存在。**判据：引用文档时用"可核对的稳定标识"（章节编号 + 一句英文描述），不要抄中文标题**；重组文档后要回头 grep 脚本里的引用是否还成立 |
| **`Start-Transcript` 抓不到子进程的输出** | 提权脚本用 `Start-Transcript` 记日志时，**只有父进程自己写的东西会进日志**；它 `&` 调起的 `powershell.exe` 子进程输出到控制台，**日志里一片空白**，极易误判成「脚本没跑」。要监控子进程进度就**回读系统状态**（设备状态、注册表值），别指望日志 |
| **提权脚本有语法错误时日志是空的** | 同上一类的组合陷阱：脚本解析失败 → `Start-Transcript` 那行根本没执行 → **日志文件 0 字节**，看起来像「什么都没发生」。所以**提权运行前先做一次真实宿主试跑**；看到空日志先怀疑语法，别怀疑权限 |
| **注册表批量写：`reg import` 又快又不会清键** | 30 个值的实测对比：`Set-ItemProperty ×30` = 94 ms、`reg add ×30` = 381 ms（每次一个进程）、**`reg import ×1` = 12 ms**。而且 `reg import` 是**合并**语义，天然不会像 `New-Item -Force` 那样重建键。注意：`.reg` 必须是 **UTF-16LE**（`Set-Content -Encoding Unicode`），DWORD 要 **8 位十六进制**（`dword:0000000a`；不足 8 位会被拒绝，实测 `dword:000000010` 直接不生效） |
| **注册表批量读：按「键」读，不要按「值」读** | 30 个值的实测：`Get-ItemProperty -Name X ×30` = 154 ms，而**每个键读一次再在内存里查值** = 4 ms（约 35×）。反面：`reg query` 每次一个进程，×30 要 371 ms |
| **目录体积统计：`Get-ChildItem -Recurse` 慢，但手写 .NET 遍历会算错** | `~\scoop`（8 GB）实测：`Get-ChildItem -Recurse -File \| Measure-Object` = 10.3 s；换成 `DirectoryInfo.EnumerateFiles` 手工栈 = 3.1 s（3.3×）。**但必须先跳过 reparse point**——`scoop\apps\<app>\current` 是 junction，跟随它会把每个 app 重复计一遍（实测 17901 MB vs 真实 8088 MB，**"更快"只是因为算错了**）。`Get-ChildItem` 默认跳过，所以朴素版对比才显得慢 |

## 验收

```powershell
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase verify
```

`setup.ps1` 末尾输出 PASS/FAIL 表；**新开一个终端**再看 PATH 类结果。
`verify-env.ps1` 另含一组 **tune 存活检查（15 项）** —— 因为累积更新会悄悄**删掉**这些值，**每次打完累积更新都值得重跑一次**。它也顺带检查 MMCSS 驱动是否真的在跑（只看注册表会漏掉"值在、服务停"的失效）。
其中「开始菜单联网搜索」一项**接受两条路径任一生效**：用户作用域的 `BingSearchEnabled`，或策略键 `DisableSearchBoxSuggestions` —— 因为前者所在的键在部分 Windows 11 版本上**内核级不可写**，只认一条路径会在那些机器上永远假 FAIL。
剩下三件脚本做不了的事：

1. **重启**，然后开新终端
2. 逐个文件类型**手动点一次**默认程序（右键 → 打开方式 → 选择其他应用 → 勾"始终"）
3. 设备有故障码 → `reset-failed-devices.ps1 -Reset`（管理员）

## 边界

| 限制 | 原因 |
|---|---|
| 默认程序无法脚本设置 | `UserChoice` 的 Deny ACL + Hash；官方 API 在 Win10 失效 |
| `rclone mount` 需要 WinFsp | 驱动安装需提权；改用系统盘符映射 |
| 便携软件不进系统"应用列表" | 天生如此，盘点必须扫目录 |
| 本方案不关 UAC、不改 DPI、不动更新策略 | 这些是用户取舍，不是"优化" |
| 需要重启才算验证完成 | 登录会话状态不会自愈 |

## 安全纪律

- 清单里的 `sha256` **必须**是发布页的真实值（脚本默认拒绝无哈希条目）
- 只从官方发布页下载；第三方"绿色版/破解版"是恶意软件主要载体
- 公开仓库不出现：真实主机名 / 内网 IP / NAS 地址 / 用户名 / `C:\Users\<真名>` / 自启项导出
