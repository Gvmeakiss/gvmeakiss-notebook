# win-ai-gaming-setup · 新 Windows 机器一键配置：AI 开发 + 游戏环境 + 系统优化

> **一台刚装好系统的 Windows 电脑，一条命令配成能干活的机器** —— 补齐 AI 开发工具链、装上常用便携软件、做完安全的系统优化，全程先快照、可回滚。
>
> 方法论的判断依据见 [SKILL.md](./SKILL.md)；这里只讲**装了什么、配了什么、怎么跑、坏了怎么办**。

```powershell
# 在一台新 Windows 机器上（建议：PowerShell 7，管理员）
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1
```

跑完输出一张 PASS/FAIL 表；退出码 0 = 选中的阶段全过，非 0 = 有阶段失败（便于脚本串联）。

---

## 总览：一次跑完能得到什么

| 维度 | 内容 | 条目数 |
|---|---|---|
| **装什么** | 引导依赖 4 项 + 开发工具链 7 项 + 编辑器/终端 2 项 + 便携软件 4 项 | **17** |
| **配什么** | 开发环境 6 类 + 系统优化 6 类 + 文件关联 | **13 类** |
| **不碰什么** | 不禁用服务、不关 UAC、不改 DPI/分辨率、不动更新策略、不关休眠/快速启动 | — |
| **可回滚** | 改动前自动拍服务+自启项快照，可逐项对比、按基线还原 | — |

---

## 一、安装的软件（完整清单）

### 1.1 引导依赖 —— `check` 阶段缺什么补什么

| 软件 | 用途 | 安装方式 | 提权 |
|---|---|---|---|
| **PowerShell 7** | 脚本运行时（脚本在 5.1 下也能跑，会自动改用 `powershell.exe` 调子脚本） | `scoop install pwsh` | 否 |
| **Scoop** | 用户级包管理器，后续一切软件的底座 | 官方安装方式 | 否 |
| **git** | 版本控制；Scoop bucket 本身也依赖它 | `scoop install git` | 否 |
| **7-Zip** | 解压 `.7z` 资产（便携软件里有） | `scoop install 7zip` | 否 |

### 1.2 开发工具链 —— `dev` 阶段，Scoop main bucket

| 包 | 用途 |
|---|---|
| `python` | 主力语言（AI / 数据处理 / 脚本） |
| `nodejs` | 前端与 Node 工具链 |
| `go` | 单文件二进制工具开发 |
| `cmake` | C/C++ 构建系统 |
| `dotnet-sdk` | .NET 开发 |
| `mingw` | Windows 上的 GCC 工具链 |
| `uv` | 极快的 Python 包/虚拟环境管理器 |

> `rust` 由配套脚本 `setup-langs.ps1` 单独处理。

### 1.3 编辑器与终端 —— `dev` 阶段，Scoop extras

| 软件 | 用途 | 跳过方式 |
|---|---|---|
| **VS Code** | 主编辑器 | `-NoEditor` |
| **Windows Terminal** | 终端（`pwsh` 的体验依赖它） | `-NoEditor` |

### 1.4 便携软件 —— `apps` 阶段，按 `apps.json` 装

**每一个都强制 SHA256 校验**（脚本默认拒绝无哈希条目），下载 → 校验 → 解压 → 折叠单层目录 → 建快捷方式 / 加 PATH。

| 软件 | 用途 | 关联的文件类型 |
|---|---|---|
| **JPEGView** | 看图。秒开，扛得住超大文件夹 | `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.webp` `.tif` `.tiff` |
| **MPC-BE** | 音视频播放，带正常播放器 UI（播放列表、变速、字幕） | `.mp4` `.mkv` `.avi` `.mov` `.webm` `.mp3` `.flac` `.wav` `.m4a` |
| **MarkText** | Markdown 实时预览编辑器 | `.md` `.markdown` |
| **rclone** | 命令行同步/备份到 NAS（SMB / WebDAV） | —（命令行工具，进 PATH） |

> 便携软件**不会出现在系统「应用列表」里**，盘点要用 `check-software.ps1` 扫目录。

### 1.5 需要手动装的（有意不自动化）

| 项目 | 为什么手动 |
|---|---|
| **GPU 驱动 + CUDA / PyTorch** | 厂商相关、体积大；且 torch 构建要按 CUDA 版本选。先装驱动，再选构建 |
| **WSL2 / Docker** | AI 开发的常见需求，但需要提权 + 虚拟化支持，交给你决定 |
| **厂商驱动**（蓝牙/网卡等） | 找不到时用 Microsoft Update Catalog 检索，**装前必须确认 INF 里含你的硬件 ID** |

---

## 二、执行的配置（完整清单）

### 2.1 开发环境（`check` + `dev` 阶段）

| 配置项 | 具体动作 | 为什么 |
|---|---|---|
| **长路径支持** | `git config --global core.longpaths true` + `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled=1` | AI 仓库嵌套深度经常超过 260 字符 |
| **开发者模式** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense=1` | HuggingFace 缓存 / pnpm 需要建符号链接 |
| **执行策略** | 当前用户设为 `RemoteSigned` | Scoop 安装所需 |
| **国内镜像** | **pip**=清华 · **npm**=npmmirror · **go**=goproxy.cn · **cargo**=rsproxy.cn · **HuggingFace**=`HF_ENDPOINT=hf-mirror.com` | 不走镜像基本下不动 |
| **PATH / Store 存根** | `fix-env.ps1` 修「装了却找不到」、应用执行别名劫持 | Windows 的 Store 存根会劫持 `python` 等命令 |
| **凭据助手** | 修正 git credential helper | — |

### 2.2 系统优化 —— `tune` 阶段

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
| 开始菜单 Bing 联网搜索 | `BingSearchEnabled=0`、`CortanaConsent=0` |

> 即 SKILL.md 里说的「CDM 9 项」。

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

### 2.3 文件关联（`link` 阶段）

让上一步装的程序出现在「打开方式」候选里，并报告**哪些类型还需你手动点一次**。

> Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，官方 COM API 在 Win10 上返回 `0x80070002` 且不生效。
> **脚本只能让程序出现在候选里，设为默认必须手动点一次**（每个类型一次，长期有效）。

### 2.4 明确不做的（这几项是用户取舍，不是「优化」）

- **不禁用任何服务** —— 按需启动的服务禁用后省不到性能，却会把输入法 / 相机 / 手柄搞坏（代价表见 SKILL.md 第一条纪律）
- **不关 UAC、不改 DPI/分辨率、不动 Windows 更新策略**
- **不关休眠 / 快速启动** —— 关休眠会连带关掉快速启动，反而让开机变慢
- **不装第三方「优化大师 / 加速器」** —— 本方案本身就是那类东西的安全替代

---

## 三、七个阶段

| 阶段 | 内容 | 管理员 | 可回滚 |
|---|---|---|---|
| `check` | **引导安装 + 检查**：PowerShell 7 / Scoop / git / 7-Zip / 长路径 / 开发者模式 / github 连通 / 磁盘 / 提权 / build+UBR | 部分 | — |
| `dev` | Scoop 装 `python node go cmake dotnet mingw uv` + **VS Code / Windows Terminal** + 国内镜像（pip/npm/go/cargo/HF）；修 PATH、Store 存根、凭据助手 | 部分 | 是（Scoop 卸载） |
| `apps` | 按 `apps.json` 装便携软件：下载 → **SHA256 校验** → 解压 → 折叠目录 → 快捷方式 / PATH | 否 | 是（删目录） |
| `drivers` | 故障设备清单（含故障码）+ Windows 更新里的驱动更新；`-InstallDrivers` 直接装 | 是 | 驱动可在设备管理器回滚 |
| `tune` | **先快照**，再改：GameDVR 关闭、MMCSS 调优、**关闭广告推荐/开始菜单联网搜索/遥测**；（可选）高性能电源计划、鼠标加速 | 是 | 是（`compare-services.ps1 -Restore`） |
| `link` | 注册关联（`-RegisterAssociations`）+ 报告哪些类型需手动点一次 + 孤儿关联检查 | 否 | 是（有注册表备份） |
| `verify` | dev 环境 / 软件清单 / 输入法健康 / 服务基线漂移，四项验收 | 否 | — |

## 四、参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `check,dev,apps,drivers,tune,link,verify` 任意组合 |
| `-Manifest` | `apps.json`（技能根目录） | 便携软件清单 |
| `-Destination` | `%USERPROFILE%\Apps` | 便携软件根目录 |
| `-SnapshotDir` | `<Destination>\_backup` | 快照与关联备份位置 |
| `-Languages` | `python,node,go,cmake,dotnet,mingw,uv` | 开发阶段要装的 Scoop 包 |
| `-NoEditor` | 关 | 跳过 VS Code + Windows Terminal |
| `-InstallDrivers` | 关 | `drivers` 阶段实际安装 Windows 更新提供的驱动 |
| `-DisableMouseAcceleration` | 关 | 把鼠标加速曲线清零（FPS 习惯） |
| `-HighPerformancePowerPlan` | 关 | 打开才切高性能（笔记本费电） |
| `-RegisterAssociations` | 关 | 打开才写关联注册（只写 HKCU） |
| `-SkipTweaks` | 关 | 只快照、不改系统 |
| `-WhatIf` | — | 预演，什么都不改 |

常用组合：

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

## 五、跑完必须做的三件事（脚本代替不了）

1. **重启，然后新开一个终端** —— PATH 与输入法栈都在登录时重建；不重启就下结论是最常见的误判
2. **手动点一次默认程序** —— Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，脚本只能让程序出现在候选里。
   右键任意该类文件 → 打开方式 → 选择其他应用 → 选中 → 勾"始终使用此应用"（每个类型一次，长期有效）
3. **设备有故障码就复位** —— `pwsh -File scripts/reset-failed-devices.ps1 -Reset`（管理员）；
   仍不行的先"完全关机"断电，再装厂商驱动

## 六、坏了怎么回滚

```powershell
# 1) 对比：哪些被改了、哪些本来就这样
pwsh -File scripts/compare-services.ps1 -Snapshot "$env:USERPROFILE\Apps\_backup\services-snapshot.csv"

# 2) 预演回滚，确认改动项与预期一致
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf

# 3) 回滚（可只挑一项）
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -Only TabletInputService
```

输入法坏了走专用路径：

```powershell
pwsh -File scripts/diagnose-ime.ps1            # 诊断：服务/进程/语言栏模式/IFEO/策略，给结论
pwsh -File scripts/diagnose-ime.ps1 -Repair    # 修复（管理员），之后必须重启
```

## 七、工具箱（同一目录，可单独用）

| 脚本 | 用途 |
|---|---|
| `snapshot-services.ps1 -OutDir <dir>` | 改动前拍照（只读） |
| `compare-services.ps1 -Snapshot <csv> [-Restore] [-Only X]` | 逐项对比 / 按基线回滚 |
| `diagnose-ime.ps1 [-Repair]` | 输入法故障诊断与修复 |
| `reset-failed-devices.ps1 [-Reset] [-Class X]` | 设备故障码分诊与复位 |
| `install-portable.ps1 -Manifest <json>` | 清单式便携安装（SHA256 必填） |
| `check-software.ps1 [-Json]` | 便携软件盘点 |
| `set-app-associations.ps1 [-Register -Apps @{}]` | 关联注册 / 现状报告 |
| `clean-orphan-associations.ps1 [-Clean]` | 卸载后的关联残留清理 |
| `audit-env.ps1` / `fix-env.ps1` / `setup-langs.ps1` / `verify-env.ps1` | 开发环境审计 / 修复 / 装语言 / 验收 |

## 八、环境与边界

- Windows 10/11 + PowerShell 7+
- `scoop` 缺失时 `dev` 阶段会自动安装（用户级，无需提权）
- `apps` 阶段的 `.7z` 资产需要 `7z`（`scoop install 7zip`）
- 脚本均为 ASCII-only（英文），文档为中文
- 默认程序无法脚本设置 —— `UserChoice` 的 Deny ACL + Hash；官方 API 在 Win10 失效
- `rclone mount` 需要 WinFsp —— 驱动安装需提权，改用系统盘符映射
- **需要重启才算验证完成** —— 登录会话状态不会自愈
