---
name: win-ai-gaming-setup
description: 把一台新的 Windows 电脑一条命令配置成「AI 开发 + 游戏」机器，并在优化出故障时回滚。当出现"新电脑怎么配""帮我装开发环境""装 Python/Node/Go/dotnet""装些好用的小软件""优化一下打游戏""优化后输入法没了/某个功能坏了""想关服务但不知道后果"等诉求时使用。唯一入口是 scripts/setup.ps1（check/dev/apps/tune/link/verify 六个阶段，幂等、可 -WhatIf）；核心纪律只有三条：不碰按需启动的服务、动系统前先拍快照、改完必须重启再验证。
agent_created: true
---

# Windows 新机配置：AI 开发 + 游戏

## 目标（什么叫"配好了"）

一台新机器跑完 `setup.ps1` 后应当满足：

| 维度 | 完成标准 |
|---|---|
| 开发 | `scoop` 可用的语言工具链（python/node/go/cmake/dotnet/mingw），PATH 与 Store 存根已修好，**新开终端**里敲 `python --version` 有输出 |
| 软件 | 便携软件就位（图片/播放器/Markdown/NAS 工具），逐个能启动，SHA256 已校验 |
| 游戏 | GameDVR 关闭、MMCSS 优先级已调；**没有禁用任何服务** |
| 系统 | 改动前有快照，能逐项对比、能回滚 |
| 输入法 | 中文能打、`Win+空格` 能切（这条最容易被"优化"搞坏） |

## 四类覆盖（核对清单）

### ① 需要配置的环境

| 项 | 怎么做 | 阶段 |
|---|---|---|
| PowerShell 7 | 缺就用 Scoop 装（`scoop install pwsh`）；脚本在 5.1 下也能跑，会自动改用 `powershell.exe` 调子脚本 | `check` |
| Scoop | 缺就按官方式安装（用户级，免提权） | `check` |
| git / 7-Zip | `scoop install git 7zip`（bucket 需要 git，`.7z` 资产需要 7z） | `check` |
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
| 便携软件 | **JPEGView**（图片）、**MPC-BE**（音视频）、**MarkText**（Markdown）、**rclone**（NAS 同步） | `apps.json`，SHA256 校验 |
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
| 某设备显示 Error / Code 43 | **与优化无关，是缺厂商驱动**。`reset-failed-devices.ps1 -Reset` 只能清状态（实测 Code 43 蓝牙约 40 秒后复发）。**实测解法**：装厂商/UWD 驱动 —— 微软通用驱动加载不了设备固件（MT7921 蓝牙就是这样：通用驱动 → "适配器命令超时" → Code 43；装上 MediaTek UWD 驱动（含 7MB 固件）后整套蓝牙协议栈立刻 OK）。找不到驱动时用 **Microsoft Update Catalog** 检索，**装前必须确认 INF 里含你的硬件 ID**（如 `USB\VID_0489&PID_E0CD&MI_00`） |
| 开机日志 `7026 ... dam` / `DCOM 10016` | 良性噪音，不用管 |
| CPU 显示 100% | 用增量采样，别信 `LoadPercentage` 瞬时值 |
| 用 `-File` 调用脚本时 `-Only A,B` 只收到一个元素 | **`-File` 模式不拆逗号数组**（`-Command` 会拆）。要么脚本内部自己 `-split ','`，要么改用 `&` 在进程内调用传数组 |
| 遍历 `HKCU\Software\Classes` 慢到几分钟 | PowerShell 逐键读实测 **281 秒**；改用原生 `reg query /s` 全量 dump 后内存过滤约 **18 秒**。注意 `/f` **不能跨反斜杠匹配键名**（`shell\open\command` 要 `/s` dump 后自己过滤） |

## 验收

```powershell
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase verify
```

`setup.ps1` 末尾输出 PASS/FAIL 表；**新开一个终端**再看 PATH 类结果。剩下三件脚本做不了的事：

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
