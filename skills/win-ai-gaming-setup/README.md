<h1 align="center">win-ai-gaming-setup</h1>

<p align="center"><b>新装的 Windows，跑一条命令配成能干活的 AI 开发机 + 能打游戏的机器</b></p>

<p align="center">
  <b>Windows 10 / 11</b> &nbsp;·&nbsp; <b>PowerShell 7</b> &nbsp;·&nbsp;
  <b>20 个软件</b> &nbsp;·&nbsp; <b>13 类配置</b> &nbsp;·&nbsp;
  <b>98 项验收</b> &nbsp;·&nbsp; <b>全程可回滚</b>
</p>

---

## 这是什么

给刚装完系统的 Windows 准备的一组脚本，替你做三件事：

1. **装东西** —— 开发工具链（Python / Node / Go / Rust / .NET / C/C++）、编辑器与终端、压缩工具、常用小工具，共 20 个。
2. **调系统** —— 关掉后台录制与广告推荐、给游戏让出调度优先级、配好国内镜像。
3. **留后路** —— 动系统之前先把服务和自启项拍一张快照，改坏了能逐项还原。

用之前不必读完全文，照着下面三步做即可。

> **两份文档分工**：本页给人看 —— 做什么、怎么用、出问题怎么办。
> 想深究或在 AI 里执行，看 [`SKILL.md`](./SKILL.md)：执行协议、判定规则、实测陷阱速查（每条含「症状 → 根因 → 判据」）。

## 三步上手

**第一步 · 先看缺什么（只读，不改任何东西）**

```powershell
pwsh -File scripts/setup.ps1 -Phase check
```

逐项报告 PowerShell 7 / Scoop / Git / 7-Zip / 长路径 / 开发者模式 / GitHub 连通性 / 磁盘空间，缺什么会说。

**第二步 · 装环境与软件（最常用）**

```powershell
pwsh -File scripts/setup.ps1 -Phase dev,apps
```

`dev` 装工具链、编辑器、国内镜像；`apps` 按 `apps.json` 装 13 项（2 个压缩工具 + 5 个便携软件 + 6 个 VC++ 运行库；便携包逐项校验 SHA256）。

**第三步 · 重启，然后验收**

```powershell
pwsh -File scripts/setup.ps1 -Phase verify
```

98 项检查，每项都是真编译、真运行，不看版本号。**不重启就验收会误判** —— PATH、输入法栈、多媒体调度驱动都在登录时重建。

想动系统优化项（后台录制、广告推荐、遥测等），先看再改：

```powershell
pwsh -File scripts/setup.ps1 -Phase tune -WhatIf   # 只打印要改什么
pwsh -File scripts/setup.ps1 -Phase tune           # 确认后再改
```

| 退出码 | 含义 |
|---|---|
| `0` | 选中的阶段全部通过 |
| 非 `0` | 至少一个阶段有失败项（便于接进脚本流水线） |

**索引**：[这是什么](#这是什么) · [三步上手](#三步上手) · [装什么](#装什么) · [配什么](#配什么) · [怎么跑](#怎么跑) · [跑完必须做](#跑完必须做) · [出问题](#出问题) · [工具箱](#工具箱) · [可能遇到的问题](#可能遇到的问题) · [边界](#边界)


## 装什么

共 20 个：

| 组 | 软件 | 数量 | 安装方式 |
|---|---|:--:|---|
| **基础** | PowerShell 7 · Scoop · Git | 3 | 官方脚本 / `scoop` |
| **压缩** | **7-Zip** · **WinRAR** | 2 | **`winget`**（无便携包，见下） |
| **开发** | Python · Node.js · Go · CMake · .NET SDK · MinGW · uv · Rust | 8 | `scoop` main bucket |
| **编辑器** | VS Code · Windows Terminal | 2 | `scoop` extras |
| **便携** | JPEGView · MPC-BE · Notepad++ · rclone · TrafficMonitor | 5 | `apps.json` + **SHA256 校验** |
| | | **20** | |

### 便携软件（5 个）

强制 SHA256（脚本默认拒绝无哈希条目）→ 下载 → 校验 → 解压 → 折叠单层目录 → 建快捷方式 / 加 PATH。

| 软件 | 用途 | 关联的文件类型 |
|---|---|---|
| **JPEGView** | 看图。秒开，扛得住超大文件夹 | `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.webp` `.tif` `.tiff` |
| **MPC-BE** | 音视频播放，带正常播放器 UI（播放列表、变速、字幕） | `.mp4` `.mkv` `.avi` `.mov` `.webm` `.mp3` `.flac` `.wav` `.m4a` |
| **Notepad++** | 文本 / 代码 / Markdown 编辑。原生、秒开、零插件即有语法高亮 | `.txt` `.md` `.markdown` `.ini` `.log` `.json` `.xml` `.yml` `.yaml` |
| **rclone** | 命令行同步 / 备份到 NAS（SMB / WebDAV） | —（进 PATH） |
| **TrafficMonitor** | 任务栏常驻 **CPU / 内存 / 网速**，开机自启 | —（系统监控） |

> **TrafficMonitor 自带调好的预设**（`presets/TrafficMonitor.config.ini`）：加粗字体、间距 10、透明背景贴合任务栏、网速简洁模式、自定义显示项与顺序、亮暗主题自动适配。
> `apps.json` 用 `configFiles` 声明它，安装器在**首次安装后按原始字节复制**（保住 UTF-8 BOM），并写入 `global_cfg.ini` 开启便携模式。
> 预设里的网卡名已清空、`[window_size]` 已剔除，换机器不会失效。

### 压缩工具

两个都装，都走 `winget`（没有可校验的便携包）。`check` 阶段先试 scoop，失败即回落到这个条目，
最后**按安装路径回读**；`verify` 阶段有独立的两行检查（`archives` 组）。

| 软件 | 包 ID | 回读路径 | 说明 |
|---|---|---|---|
| **7-Zip** | `7zip.7zip` | `%ProgramFiles%\7-Zip\7z.exe` | 同时是便携软件的解压器依赖 |
| **WinRAR** | `RARLab.WinRAR` | `%ProgramFiles%\WinRAR\WinRAR.exe` | `.rar` 与它的 UI；40 天试用后带弹窗继续可用，长期用请买授权 |
### 清单机制（`apps.json`）

| 字段 | 作用 |
|---|---|
| `source` | 缺省 = 便携包；`winget` = 交给 winget 装并回读 `verifyPath` |
| `sha256` | 便携条目**必填**，值为官方资产的实测哈希 |
| `exe` | **相对安装根目录**的路径（JPEGView 有三个顶层目录，必须写 `JPEGView64\JPEGView.exe`） |
| `assoc` | 该软件应出现在哪些类型的"打开方式"候选里 |
| `configFiles` | 首次安装后要落盘的配置文件（`{ 目标文件名: 相对技能根的预设路径 }`），**重跑不覆盖** |
| `notes` | 该条目的已知坑与注意事项 |

> [!NOTE]
> 便携软件**不会出现在系统「应用列表」里**（winget 装的会）。盘点要跑 `check-software.ps1` 扫目录。

---

## 配什么

### 开发环境（6 类）

| 配置项 | 动作 |
|---|---|
| **长路径** | `core.longpaths=true` + `LongPathsEnabled=1` —— AI 仓库嵌套经常超 260 字符 |
| **开发者模式** | `AllowDevelopmentWithoutDevLicense=1` —— HuggingFace 缓存 / pnpm 要建符号链接 |
| **执行策略** | 当前用户 `RemoteSigned` |
| **国内镜像** | pip=清华 · npm=npmmirror · go=goproxy.cn · cargo=rsproxy.cn · HF=`hf-mirror.com` |
| **PATH / Store 存根** | 修「装了却找不到」，以及 Store 别名劫持 `python` 等命令 |
| **凭据助手** | 修正 git credential helper |

> [!IMPORTANT]
> 镜像配置**收尾会逐项回读真实值**。每个镜像都被"对应工具是否在 PATH"守卫着 ——
> 工具没装成功就整段跳过，而硬编码的汇总行会谎报"已生效"。

### 系统优化（6 类）

> [!WARNING]
> **`reg import` 会静默漏写。** 实测 Windows 11 26xxx：`reg import` 返回 `The operation completed successfully`（退出码 0），
> 但在 `HKCU\...\CurrentVersion\ContentDeliveryManager` 下**一个新值都没创建** —— 连全新建的值名都被丢弃；
> 同一时刻用 `reg add` 或 `Set-ItemProperty` 写同一个值则成功。
> 本项目原来就靠批量 `.reg` 写入（比逐条写快 8 倍），因此这一路静默失败表现为「tune 报 2 个失败但没人能解释」。
> 现在每个值导入后都会回读，**没落地的用注册表提供程序补写一次再回读**，并在日志里点名哪几个值走了兜底。
**先创建还原点、再拍快照**：还原点为注册表写入提供回滚路径（`Checkpoint-Computer` 默认有 24 小时去重，脚本会临时把 `SystemRestorePointCreationFrequency` 置 0，创建后回读列表，再恢复护栏）；快照记录服务启动类型 + 自启项。每一条都是单个注册表写入、逐条报告。

| 类 | 内容 |
|---|---|
| **游戏** | 关 Xbox Game DVR；MMCSS `SystemResponsiveness=10`、`NetworkThrottlingIndex=0xffffffff`；`Games` 任务四项（GPU Priority 8 / Priority 6 / Scheduling Category High / SFIO High） |
| **广告与推荐** | 静默推广 App、开始菜单建议、锁屏广告、Windows 提示、资源管理器同步广告 —— 全关（共 9 项） |
| **开始菜单联网搜索** | 走**策略键** `DisableSearchBoxSuggestions=1` + `ConnectedSearchUseWeb=0`、`AllowCortana=0` |
| **遥测** | 策略 `AllowTelemetry` —— **按 SKU 门控**：企业版/教育版/Server 写 `0`，家庭版/专业版写 `1`。改策略，不是杀服务 |
| **遥测任务与出网** | 逐条禁用遥测计划任务（**存在才处理**，清单随 build 变化）+ 防火墙按组阻断 `DiagTrack`（可 `-Action Allow` 回退，不删规则） |
| **安全兜底** | **还原点**是真正的回滚路径；`PreventDeviceEncryption=1`（只拦未来的自动加密，不动已加密卷）；`EnablePeriodicBackup=1` 顺带写（见下方警告：新版本上是空操作） |
| **网络礼貌** | `DODownloadMode=1`：更新交付留在局域网，不向互联网上传 |
| **磁盘保洁** | Storage Sense 清回收站（保留 30 天）。**下载目录自动删除保持关闭** —— 会误删用户下载的安装包，省的空间不值这个风险 |
| **右键菜单** | 恢复 Win11 折叠之前的经典菜单（CLSID `InprocServer32` 默认值置空），重启 Explorer 生效 |
| **电源 / 鼠标** | 默认不动；`-HighPerformancePowerPlan`、`-DisableMouseAcceleration` 显式开启才生效 |
| **文件关联** | 让装好的程序进入候选，报告哪些类型仍需手动点一次 |

> [!IMPORTANT]
> **`AllowTelemetry=0` 在家庭版/专业版上是空操作。** `0`（Security/Off）只有企业版、教育版、Server 接受；
> 消费版会静默忽略它 —— 于是脚本"成功"、注册表里也确实写着 0，而诊断数据照传。
> winutil、Win11Debloat、Sycnex、W4RH4WK 全都无条件写 0，只有 Sophia-Script 做了 SKU 门控。
> 本项目跟着做门控，`verify-env.ps1` 也按 SKU 计算期望值，不再把"写了没人读的值"当成果。
> [!WARNING]
> **`EnablePeriodicBackup` 会延迟生效，别把它当"立刻可用"的安全网。**
> 实测时间线：写入后立即查 `RegBack` 是 **0 字节**（重启后、手动 `Start-ScheduledTask` 后都是 0），
> 同期该任务的触发器与动作在注册表视图里也是空的，`SIT` 服务早已不存在 —— 于是我一度判定"这个 build 已移除该功能"。
> **两天两次重启后再查：`RegBack` 里是 110 MB 真实 hive。** 结论修正为：Windows 在下一次启动/空闲点填充它，不响应手动触发。
> 因此 `verify-env.ps1` 检查的是 **`RegBack` 的实际字节数**而不是开关值，
> 未填充时只报信息项并提示"以还原点为准"。**判据：不能凭"当前是 0 字节"断定功能不存在；要给它一个启动周期再判。**

> [!NOTE]
> 联网搜索为什么不用 `BingSearchEnabled`：`HKCU\...\CurrentVersion\Search` 在 Windows 11 24H2+ 上
> **会被内核层拒绝写入**（`reg import` 报 `Not all data was successfully written`），而它的 ACL 看着仍是当前用户 FullControl。
> 策略键实测可写且优先级更高，不是降级方案。

### 明确不做（是取舍，不是「优化」）

- **不禁用任何服务** —— 按需启动的服务禁用后省不到性能，却会把输入法 / 相机 / 手柄搞坏
- **不关 UAC、不改 DPI / 分辨率、不动 Windows 更新策略**
- **不关休眠 / 快速启动** —— 关休眠会连带关掉快速启动，开机反而更慢
- **不装第三方「优化大师 / 加速器」** —— 本方案就是那类东西的安全替代

### 别人写错了，我们不复刻（逐条有出处）

审阅 winutil / Win11Debloat / Sophia / Bloatynosy / Hyyote / PC-Tuning / W4RH4WK / Sycnex 的真实源码后，
以下做法在**机制层面就是错的或有害**，本项目一条都不采用：

| 常见做法 | 为什么不做 |
|---|---|
| `bcdedit /set useplatformclock true`、`disabledynamictick yes`、改写 ACPI 表禁用 HPET | 方向相反。Win8+ 用 invariant TSC，平台计时器 "access latency 更高、多核共享"（[Microsoft QPC 文档](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)） |
| MMCSS `SystemResponsiveness` 调到 0 或 1 | **文档化 no-op**：低于 10 会被夹到 20（默认值）。所以本方案写 10，恰好是有效边界 |
| 直接改 `...\PowerSettings\...\ValueMax/ValueMin` 来"关核心停靠" | 那是**元数据树**，不是活动方案。正确写法 `powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100` |
| 批量 `Stop-Service`/`Set-Service -StartupType Disabled`（含 `SharedAccess`、`WbioSrvc`、Xbox 三服务） | 热点断、Windows Hello 指纹失效、Game Pass 起不来。winutil 的**标准预设**里就含 `SharedAccess` 禁用 |
| hosts 阻断 `*.msftncsi.com` / `sls.update.microsoft.com` / Store 端点 | W4RH4WK 自己的注释：系统误判无网络、更新失败、Store 打不开 |
| `Disable-BitLocker` 当"必备优化" | 解密在用卷，撤销无法恢复原保护器 |
| 硬编码 `ControlSet001` | 应使用 `CurrentControlSet`（控制集编号会变） |
| `Dism /ResetBase` | 之后无法卸载已安装的更新 |
| 强制删 OneDrive / Edge | 无空目录检查会删掉用户已同步的文件；Edge 强删连带 WebView2 依赖 |
| `Disable-ScheduledTask -TaskName "\完整\路径\任务名"` | 路径不解析，静默 no-op（要 `-TaskPath` + `-TaskName` 分开传） |
| 删 ETW 通道 / 事件日志 / 桩化 `wer.dll`（"Nuke" 类脚本） | 摧毁**验证延迟所需的追踪能力**，之后无法证明任何优化有效 |

### 可选手工项（脚本故意不做，但确实有效）

这三件事无法安全脚本化，或者属于取舍，所以不放进 `-Phase tune`：

**① 杀毒软件信任区（对游戏载入最有效的一条）**

实时扫描会对**每一次文件读取**做检查。把游戏与开发目录加入信任区，能明显减少载入等待与补丁校验卡顿。

| 目录 | 典型体积 |
|---|---|
| `C:\Program Files (x86)\Steam\steamapps` | 74 GB |
| WeGame 游戏目录（如 `C:\WeGameApps`） | 52 GB |
| 代码仓库根目录 | 视项目 |

- **Windows Defender**：设置 → 病毒和威胁防护 → 排除项 → 添加文件夹
- **火绒**：安全设置 → 信任区 → 添加目录（配置是二进制，只能手工点）

> 注意：这是一次**安全面收缩**。只排除"只读的游戏/代码内容"，不要排除 `Downloads`、`AppData` 或整个盘。

**② 预装 App 清理（省磁盘，不省性能）**

实测一台机器 144 个 AppX 包里：34 个框架包、53 个系统不可移除、**62 个可移除**，合计约 9 GB ——
但后台真正在跑的只有 OneDrive。所以这事的收益是**磁盘**，不是帧率。

**两条纪律，否则会出事：**

1. **显式清单，不做"白名单反转"**。Sycnex 的写法是"不在白名单里就删"，
   而按体积排序第一个可移除包往往是**用户自己装的软件**（实测是 4.5 GB 的编辑器）。
2. **必须用 Windows PowerShell 5.1 执行**。PS 7 下 `Remove-AppxPackage -AllUsers` 报
   「拒绝访问」、`Get-AppxProvisionedPackage` 报「没有注册类」—— 这是 WinRT 互操作差异，不是权限问题。

安全清单（游戏机不需要，且不连带依赖）：

```
Microsoft.GamingApp / Microsoft.XboxGamingOverlay / Microsoft.GamingServices
Clipchamp.Clipchamp / Microsoft.MicrosoftSolitaireCollection / Microsoft.Todos
Microsoft.WindowsFeedbackHub / Microsoft.GetHelp / Microsoft.MicrosoftOfficeHub
Microsoft.MicrosoftStickyNotes
```

**绝不要动**：`Microsoft.PowerShell`、`Microsoft.WindowsStore`、`Microsoft.Windows.Photos`、
`Microsoft.Paint`、`Microsoft.ScreenSketch`、`MicrosoftWindows.Client.WebExperience`（Shell 体验）、
语言包、`Microsoft.VCLibs.*` / `Microsoft.UI.Xaml.*`（框架）、以及任何非 Microsoft 发布者。

删完记得**反预置**（`Remove-AppxProvisionedPackage`），否则新用户或功能更新会装回来。

**③ 休眠（按机器取舍）**

`powercfg /hibernate off` 删除 `hiberfil.sys`（实测 21.8 GB 内存的机器上是 **8.72 GB**），
代价是失去休眠与**快速启动**。两个细节：

- `powercfg /h off` **不会**把 `HiberbootEnabled` 改成 0，要单独写，否则"关机"仍是伪关机
- 快速启动的收益在 NVMe 上有限（实测冷启动 26–36 秒），而它是"关机后状态不干净"类怪问题的常见来源

本技能**默认不动休眠**（见「明确不做」），这条留给需要空间的机器自己决定。

---

## 怎么跑

### 七个阶段

| 阶段 | 内容 | 管理员 | 可回滚 |
|---|---|:--:|---|
| `check` | 引导安装 + 检查：pwsh / Scoop / git / 7-Zip / 长路径 / 开发者模式 / GitHub 连通 / 磁盘 / 提权 / build+UBR | 部分 | — |
| `dev` | 装语言工具链 + VS Code / Windows Terminal + 国内镜像；修 PATH、Store 存根、凭据助手 | 部分 | 是 |
| `apps` | 按 `apps.json` 装 13 项（8 个 winget + 5 个便携，便携包校验 SHA256） | 否 | 是 |
| `drivers` | 故障设备清单（含故障码）+ Windows 更新里的驱动；`-InstallDrivers` 直接装 | 是 | 设备管理器可回滚 |
| `tune` | **先快照**再改；回读 `sc query MMCSS` 是否 RUNNING | 是 | 是 |
| `link` | 注册关联 + 报告哪些类型需手动点一次 + 孤儿关联检查 | 否 | 是 |
| `verify` | **98 项验收** | 否 | — |

`verify` 验什么：

| 组别 | 项数 | 判据要点 |
|---|:--:|---|
| `hygiene` | 1 | 每个 `.ps1` 在 **PS 7 与 PS 5.1 下都能解析** |
| `tweaks` | 49 | 含 **MMCSS 驱动是否真在跑**（只看注册表会漏掉「值在、服务停」）、**还原点/注册表备份/BitLocker 自动加密拦截**、经典右键菜单、遥测任务与 DiagTrack 防火墙、**WPBT 阻断/设备元数据/备份深度/后台应用/锁屏通知/广告ID/活动与输入遥测/Edge 预加载** |
| 各语言链 | 30 | **真编译真运行**，不看 `--version`（python / node / go / rust / java / dotnet / cpp） |
| 其它 | 5 | git / gh / ssh / **7-Zip 与 WinRAR**（`archives` 组） |
| `system` | 7 | 页面文件是否系统管理 / 启动项有无安装残留 / 网卡省电 PnPCapabilities=24 / 显卡驱动年龄（信息项） / AMD 遥测是否关闭（信息项） / **是否存在可用还原点**（信息项） |
| `runtimes` | 6 | **VC++ 2005/2008（SxS）、2010、2012、2013、2015-2022 逐代检查 x86+x64**；.NET 3.5 为信息项（镜像是系统外的必需件，游戏起不来时最常见的原因） |

### 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `check,dev,apps,drivers,tune,link,verify` 任意组合 |
| `-Profile` | 空 | **预设包，覆盖 `-Phase`**：`minimal`（check/apps/link，不碰系统）· `dev`（+开发链+验收）· `full`（含 drivers/tune） |
| `-Manifest` | `apps.json` | 应用清单 |
| `-Destination` | `%USERPROFILE%\Apps` | 便携软件根目录 |
| `-SnapshotDir` | `<Destination>\_backup` | 快照与关联备份 |
| `-Languages` | `python,nodejs,go,cmake,dotnet-sdk,mingw,uv` | 必须是真实 scoop 清单名；`node` / `dotnet` / `python3` / `golang` 会自动归一化 |
| `-NoEditor` | 关 | 跳过 VS Code + Windows Terminal |
| `-InstallDrivers` | 关 | `drivers` 阶段实际安装驱动 |
| `-HighPerformancePowerPlan` | 关 | 切高性能电源计划 |
| `-DisableMouseAcceleration` | 关 | 鼠标加速曲线清零 |
| `-DisableSleepOnAC` | 关 | 交流供电下不睡眠（保留关屏）。给 S0 现代待机会"睡死"的台式机/迷你主机用 |
| `-RegisterAssociations` | 关 | 写关联注册（**只写 HKCU**） |
| `-SkipTweaks` | 关 | 只快照、不改系统 |
| `-IncludeOptionalApps` | 关 | 安装清单里 `optional: true` 的条目。**当前清单没有可选条目**，机制保留 |
| `-WhatIf` | — | 预演。**会转发给支持 `-WhatIf` 的子脚本** |

> [!TIP]
> `-WhatIf` 真的什么都不做：`apps` 阶段只打印"将下载哪个 URL / 将对哪个包 `winget install`"，
> 不落盘、不装包。这一点有逆测试守着（见 `SKILL.md` 的预演条目）。

---

## 跑完必须做

脚本代替不了的三件事：

1. **重启，然后新开终端** —— PATH 与输入法栈在登录时重建
2. **手动点一次默认程序** —— Windows 的 `UserChoice` 有 Deny ACL + Hash 保护，脚本只能让程序出现在候选里。
   右键该类文件 → 打开方式 → 选择其他应用 → 勾"始终使用"（每个类型一次，长期有效）
3. **设备有故障码就复位** —— `pwsh -File scripts/reset-failed-devices.ps1 -Reset`（管理员）。
   先试 `pnputil /restart-device`（秒级、免重启），失败才降级到 disable/enable + 重扫

> [!WARNING]
> **打完累积更新后，重跑一次 `verify-env.ps1`。**
> 实测两次：累积更新会**删掉** `tune` 写入的注册表值 —— 不是改成别的值，是**直接删除**
> （`SystemResponsiveness`、`GlobalUserDisabled`、各项广告开关都中招过）。
> 所以那组 **tune 存活检查把「值缺失」直接判 FAIL** —— 只看值等不等于期望，会把「被删了」误判成「本来就没设置」。

---

## 出问题

### 回滚

```powershell
# 1) 对比：哪些被改了、哪些本来就这样
pwsh -File scripts/compare-services.ps1 -Snapshot "$env:USERPROFILE\Apps\_backup\services-snapshot.csv"

# 2) 预演回滚
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf

# 3) 回滚，可只挑一项
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -Only TabletInputService
```

`-Phase tune` 每次还会写两样东西到 `-SnapshotDir`（默认 `%USERPROFILE%\Apps\_backup`）：

| 产物 | 用途 |
|---|---|
| `setup-<时间戳>.log` | **完整 transcript**。出问题先看它，不用凭记忆复述 |
| `tune-undo-<时间戳>.ps1` | **逐项撤销脚本**：记录每个值在写入**之前**的实际内容，按项回退；原来不存在的值会被删除，而不是写一个猜的默认值 |

> 还原点是"整机回到某一刻"的粗粒度回退；`tune-undo-*.ps1` 是"只退这一条"的手术刀。两者都要有。
> 撤销脚本在提权用户会话里跑：`pwsh -File <撤销脚本>`。

### 输入法坏了

```powershell
pwsh -File scripts/diagnose-ime.ps1            # 诊断：服务 / 进程 / 语言栏模式 / IFEO / 策略
pwsh -File scripts/diagnose-ime.ps1 -Repair    # 修复（管理员），之后必须重启
```

### 游戏崩溃 / 黑屏 / 进游戏就挂

这不是"回滚"能解决的，通常是显卡驱动挂起（TDR）：

```powershell
# 1) 取证：内核看门狗转储（设备恢复后记录仍在）
Get-ChildItem C:\Windows\LiveKernelReports\WATCHDOG\*.dmp | Sort-Object LastWriteTime -Descending

# 2) 恢复设备（秒级，不用重启）
pnputil /restart-device "<InstanceId>"     # 或 scripts/reset-failed-devices.ps1 -Reset
```

仍反复就按 `SKILL.md` 的「显卡稳定性」小节：加大 `TdrDelay` → 关 AMD `EnableUlps` → 散热 / 驱动重装。

> **症状识别**：**屏幕黑一下又恢复** = 又 TDR 了；**游戏分辨率/画质被改回通用值** = 显卡挂掉后游戏重跑了硬件检测，是症状不是原因。

---

## 工具箱

13 个可单独用的脚本 + 入口 `setup.ps1` + 自举 `bootstrap.ps1` + 自测 `test-tune-core.ps1`。
全部自包含、支持 `Get-Help`。

| 新东西 | 解决什么 |
|---|---|
| `bootstrap.ps1` | **无 git 自举**：新机没 git 就 clone 不了仓库，而仓库负责装 git —— 死循环。它用 HTTPS 下载仓库 zip 解压后转交 `setup.ps1` |
| `test-tune-core.ps1` | 纯函数自测（18 条断言，零依赖、秒级）：DWORD 渲染、撤销脚本转义、版本门控 |
| `lib/tune-core.ps1` | 上述纯函数的实现，被 `setup.ps1` dot-source；`check-script-hygiene.ps1` 现在**递归**扫描（否则会漏掉它） |

| 组 | 脚本 | 用途 |
|---|---|---|
| **开工前**（只读） | `check-script-hygiene.ps1` | 每个 `.ps1` 的编码 + **PS 7 / PS 5.1 双宿主解析**（不执行，秒级） |
| | `audit-env.ps1` | 开发环境审计（工具链 / 镜像 / PATH / 存根） |
| | `check-software.ps1` | 软件盘点（含便携软件扫目录） |
| | `snapshot-services.ps1` | 改动前拍照：服务启动类型 + 自启项 |
| | `set-app-associations.ps1` | 关联现状报告（不加 `-Register` 就是只读） |
| **安装与修复** | `setup-langs.ps1` | 装语言工具链 + 配镜像（含 rust） |
| | `install-portable.ps1` | 清单式安装：便携包（**SHA256 必填**）+ `winget` 条目 |
| | `fix-env.ps1` | 修「装了却找不到」：PATH / Store 存根 / 凭据助手 |
| **优化与回滚** | `compare-services.ps1` | 与快照逐项对比 / 按基线回滚 |
| | `reset-failed-devices.ps1` | 设备故障码分诊与复位 |
| | `clean-orphan-associations.ps1` | 卸载后的关联残留清理 |
| **故障与验收** | `diagnose-ime.ps1` | 输入法诊断与修复 |
| | `verify-env.ps1` | **验收**：真编译真运行 + 软件清单 + 输入法 + 服务漂移 + tune 存活 15 项 + 脚本 hygiene |

### 测量优先：先证明再优化

优化最贵的成本不是改错，而是**改完不知道有没有用**。下面这些工具全部能在 winget 装到，
而且都是"从进程外观察"的方式 —— 注入式覆盖层在 CS2 的 Trusted Mode / Vanguard 下会被直接拦掉，
ETW 采集不受影响。

| 工具 | 证明什么 | 安装 |
|---|---|---|
| **PresentMon** | 逐帧 CPU/GPU 时长 + 显示延迟（ETW，**不注入游戏进程**） | `winget install Intel.PresentMon.Console` |
| **CapFrameX** | 在 PresentMon 之上算 1% / 0.1% 低帧与卡顿，判断"平均提升"还是"一致性提升" | `winget install CXWorld.CapFrameX` |
| **HWiNFO** | 真实功耗、频率、温度、**降频原因标记** —— 判断是被功耗墙还是被带宽卡住 | `winget install REALiX.HWiNFO` |
| **LatencyMon** | DPC/ISR 耗时与硬缺页 —— 判断卡顿来自驱动而不是显卡 | `winget install Resplendence.LatencyMon` |
| **GPU-Z** | 适配器型号、显存类型、**总线位宽**、驱动版本 | `winget install TechPowerUp.GPU-Z` |
| **DDU** | 驱动残留清理。**只在驱动装坏或换厂商时用**，不是日常维护 | [Wagnardsoft](https://www.wagnardsoft.com/display-driver-uninstaller-ddu) |

最小协议：同一场景跑 3 次、丢掉第一次热身、同时记录 HWiNFO，**一次只改一个变量**，
结论里同时给平均帧、1% 低帧与显示延迟。只报平均帧的"优化"基本不可信。

> **`check-script-hygiene.ps1` 为什么必须早跑**：无 BOM 的 UTF-8 脚本会被 `ParseFile` 按 UTF-8 读、
> 被 `powershell.exe -File` 按 ANSI 读 ⇒ **"校验通过"是假通过**。计划任务永远用 5.1，这类脚本会以 `0x1` 静默失败，
> 而任务历史仍显示"成功"。它已挂进 `verify-env.ps1`，**WARN 与 FAIL 都拦截**。

---

## 可能遇到的问题

首页只放结论。下面这些是**已经修好、但重装或换机器时仍可能撞上**的，完整判据在
[`SKILL.md`](./SKILL.md) 的陷阱表里；每条都写了「症状 → 根因 → 判据」。

| 症状 | 根因 | 在哪查 |
|---|---|---|
| 软件"装了"但找不到 / 没快捷方式 | `exe` 相对路径写错，或安装器只看命令退出码 | 清单 `exe` + 回读 `verified N/M` |
| 盘点报某个软件缺失，实际已装 | 只扫了便携目录，winget/官网装的在别处 | 清单 `altPaths` |
| 计划任务静默失败、退出码 `0x1` | 无 BOM 的 UTF-8 脚本被 5.1 按 ANSI 解码 | 先跑 `check-script-hygiene.ps1` |
| `.7z` 解不开 | 用了精简版 `7zr.exe`（没有 ZIP 编解码器） | 装完整 7-Zip |
| 打完累积更新后优化失效 | 更新会**直接删除**注册表值，不是改值 | 重跑 `verify-env.ps1` |
| 中文标签变乱码 | 改第三方 ini 时丢了 UTF-8 BOM | 显式带 BOM 写 |
| **Edge 自启项删了又回来** | Edge 更新（实测 156.x）会重新写 `HKCU\...\Run\MicrosoftEdgeAutoLaunch_*` | `verify-env.ps1` 的 `startup leftovers` 会红；删值重跑即可 |
| **提权下 `-Phase check` 失败** | scoop 安装器拒绝以管理员运行（`Abort.`），而旧版 check 无条件装 scoop | 已修：`dev` 阶段才要求 scoop，且提权时给出手动命令 |
| 撤销脚本跑完仍有遗留 | 只覆盖注册表/任务/防火墙/电源四类写入，文件级操作不在内 | 看撤销脚本里的 `# ` 注释清点范围 |

## 边界

| 限制 | 说明 |
|---|---|
| 系统 / Shell | Windows 10/11；建议 PowerShell 7+（5.1 能跑，但脚本必须 ASCII-only 或带 BOM） |
| `scoop` 缺失 | `check` 阶段会自动装（用户级、免提权）。直接单跑 `dev` 会报 `scoop not found` —— 预期行为 |
| `.7z` 资产 | 需要 `7z`。`.zip` 用系统内置支持，不需要外部工具 |
| `7zr.exe` | 精简版**没有 ZIP 编解码器** —— 只能解 `.7z` |
| 脚本编码 | 本目录所有 `.ps1` 均为 **ASCII-only**（英文），文档为中文 |
| 默认程序 | **无法脚本设置为默认** —— `UserChoice` 的 Deny ACL + Hash |
| `rclone mount` | 需要 WinFsp（驱动、要提权）；改用系统盘符映射 |
| 验收 | **需要重启** —— 登录会话状态不会自愈 |

---

<p align="center"><sub>
<b>SKILL.md</b> = 方法论与判断依据（含实测踩坑判据） &nbsp;·&nbsp;
<b>docs/</b> = 实测记录与审计方法
</sub></p>

<p align="center"><sub>
<a href="./SKILL.md">方法论 → SKILL.md</a> &nbsp;·&nbsp;
<a href="../../windows-tuning/01-baseline.md">基线实测记录</a>
</sub></p>

---

<p align="right"><sub><a href="../../README.md">← 返回笔记本目录</a> · <a href="./SKILL.md">SKILL.md（AI 执行）</a></sub></p>
