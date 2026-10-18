<h1 align="center">win-ai-gaming-setup</h1>

<p align="center"><b>新装的 Windows，跑一条命令配成能干活的 AI 开发机 + 能打游戏的机器</b></p>

<p align="center">
  <b>Windows 10 / 11</b> &nbsp;·&nbsp; <b>PowerShell 7</b> &nbsp;·&nbsp;
  <b>20 个软件</b> &nbsp;·&nbsp; <b>13 类配置</b> &nbsp;·&nbsp;
  <b>55 项验收</b> &nbsp;·&nbsp; <b>全程可回滚</b>
</p>

---

## 这是什么

给刚装完系统的 Windows 准备的一组脚本，替你做三件事：

1. **装东西** —— 开发工具链（Python / Node / Go / Rust / .NET / C/C++）、编辑器与终端、压缩工具、常用小工具，共 20 个。
2. **调系统** —— 关掉后台录制与广告推荐、给游戏让出调度优先级、配好国内镜像。
3. **留后路** —— 动系统之前先把服务和自启项拍一张快照，改坏了能逐项还原。

用之前不必读完全文，照着下面三步做即可。

> **两份文档分工**：本页给人看 —— 做什么、怎么用、出问题怎么办。
> 想深究或在 AI 里执行，看 [`SKILL.md`](./SKILL.md)：执行协议、判定规则、62 条实测陷阱。

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

`dev` 装工具链、编辑器、国内镜像；`apps` 装 7 个应用（两个压缩工具 + 五个便携软件，每个都校验 SHA256）。

**第三步 · 重启，然后验收**

```powershell
pwsh -File scripts/setup.ps1 -Phase verify
```

55 项检查，每项都是真编译、真运行，不看版本号。**不重启就验收会误判** —— PATH、输入法栈、多媒体调度驱动都在登录时重建。

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

**先拍快照再动手**（服务启动类型 + 自启项），每一条都是单个注册表写入、逐条报告。

| 类 | 内容 |
|---|---|
| **游戏** | 关 Xbox Game DVR；MMCSS `SystemResponsiveness=10`、`NetworkThrottlingIndex=0xffffffff`；`Games` 任务四项（GPU Priority 8 / Priority 6 / Scheduling Category High / SFIO High） |
| **广告与推荐** | 静默推广 App、开始菜单建议、锁屏广告、Windows 提示、资源管理器同步广告 —— 全关（共 9 项） |
| **开始菜单联网搜索** | 走**策略键** `DisableSearchBoxSuggestions=1` + `ConnectedSearchUseWeb=0`、`AllowCortana=0` |
| **遥测** | 策略 `AllowTelemetry=0` —— **改策略，不是杀服务** |
| **电源 / 鼠标** | 默认不动；`-HighPerformancePowerPlan`、`-DisableMouseAcceleration` 显式开启才生效 |
| **文件关联** | 让装好的程序进入候选，报告哪些类型仍需手动点一次 |

> [!NOTE]
> 联网搜索为什么不用 `BingSearchEnabled`：`HKCU\...\CurrentVersion\Search` 在 Windows 11 24H2+ 上
> **会被内核层拒绝写入**（`reg import` 报 `Not all data was successfully written`），而它的 ACL 看着仍是当前用户 FullControl。
> 策略键实测可写且优先级更高，不是降级方案。

### 明确不做（是取舍，不是「优化」）

- **不禁用任何服务** —— 按需启动的服务禁用后省不到性能，却会把输入法 / 相机 / 手柄搞坏
- **不关 UAC、不改 DPI / 分辨率、不动 Windows 更新策略**
- **不关休眠 / 快速启动** —— 关休眠会连带关掉快速启动，开机反而更慢
- **不装第三方「优化大师 / 加速器」** —— 本方案就是那类东西的安全替代

---

## 怎么跑

### 七个阶段

| 阶段 | 内容 | 管理员 | 可回滚 |
|---|---|:--:|---|
| `check` | 引导安装 + 检查：pwsh / Scoop / git / 7-Zip / 长路径 / 开发者模式 / GitHub 连通 / 磁盘 / 提权 / build+UBR | 部分 | — |
| `dev` | 装语言工具链 + VS Code / Windows Terminal + 国内镜像；修 PATH、Store 存根、凭据助手 | 部分 | 是 |
| `apps` | 按 `apps.json` 装 7 个应用（2 个 winget + 5 个便携） | 否 | 是 |
| `drivers` | 故障设备清单（含故障码）+ Windows 更新里的驱动；`-InstallDrivers` 直接装 | 是 | 设备管理器可回滚 |
| `tune` | **先快照**再改；回读 `sc query MMCSS` 是否 RUNNING | 是 | 是 |
| `link` | 注册关联 + 报告哪些类型需手动点一次 + 孤儿关联检查 | 否 | 是 |
| `verify` | **55 项验收** | 否 | — |

`verify` 验什么：

| 组别 | 项数 | 判据要点 |
|---|:--:|---|
| `hygiene` | 1 | 每个 `.ps1` 在 **PS 7 与 PS 5.1 下都能解析** |
| `tweaks` | 15 | 含 **MMCSS 驱动是否真在跑**（只看注册表会漏掉"值在、服务停"） |
| 各语言链 | 30 | **真编译真运行**，不看 `--version`（python / node / go / rust / java / dotnet / cpp） |
| 其它 | 5 | git / gh / ssh / **7-Zip 与 WinRAR**（`archives` 组） |
| `system` | 4 | 页面文件是否系统管理 / 启动项有无安装残留 / 网卡省电 PnPCapabilities=24 / 显卡驱动年龄（信息项） |

### 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Phase` | `all` | `check,dev,apps,drivers,tune,link,verify` 任意组合 |
| `-Manifest` | `apps.json` | 应用清单 |
| `-Destination` | `%USERPROFILE%\Apps` | 便携软件根目录 |
| `-SnapshotDir` | `<Destination>\_backup` | 快照与关联备份 |
| `-Languages` | `python,nodejs,go,cmake,dotnet-sdk,mingw,uv` | 必须是真实 scoop 清单名；`node` / `dotnet` / `python3` / `golang` 会自动归一化 |
| `-NoEditor` | 关 | 跳过 VS Code + Windows Terminal |
| `-InstallDrivers` | 关 | `drivers` 阶段实际安装驱动 |
| `-HighPerformancePowerPlan` | 关 | 切高性能电源计划 |
| `-DisableMouseAcceleration` | 关 | 鼠标加速曲线清零 |
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

13 个可单独用的脚本 + 唯一入口 `setup.ps1`。全部自包含、支持 `Get-Help`。

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

> **`check-script-hygiene.ps1` 为什么必须早跑**：无 BOM 的 UTF-8 脚本会被 `ParseFile` 按 UTF-8 读、
> 被 `powershell.exe -File` 按 ANSI 读 ⇒ **"校验通过"是假通过**。计划任务永远用 5.1，这类脚本会以 `0x1` 静默失败，
> 而任务历史仍显示"成功"。它已挂进 `verify-env.ps1`，**WARN 与 FAIL 都拦截**。

---

## 可能遇到的问题

首页只放结论。下面这些是**已经修好、但重装或换机器时仍可能撞上**的，完整判据（62 条）在
[`SKILL.md`](./SKILL.md) 的陷阱表里；每条都写了「症状 → 根因 → 判据」。

| 症状 | 根因 | 在哪查 |
|---|---|---|
| 软件"装了"但找不到 / 没快捷方式 | `exe` 相对路径写错，或安装器只看命令退出码 | 清单 `exe` + 回读 `verified N/M` |
| 盘点报某个软件缺失，实际已装 | 只扫了便携目录，winget/官网装的在别处 | 清单 `altPaths` |
| 计划任务静默失败、退出码 `0x1` | 无 BOM 的 UTF-8 脚本被 5.1 按 ANSI 解码 | 先跑 `check-script-hygiene.ps1` |
| `.7z` 解不开 | 用了精简版 `7zr.exe`（没有 ZIP 编解码器） | 装完整 7-Zip |
| 打完累积更新后优化失效 | 更新会**直接删除**注册表值，不是改值 | 重跑 `verify-env.ps1` |
| 中文标签变乱码 | 改第三方 ini 时丢了 UTF-8 BOM | 显式带 BOM 写 |

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
<b>SKILL.md</b> = 方法论与判断依据（含 62 条踩坑判据） &nbsp;·&nbsp;
<b>docs/</b> = 实测记录与审计方法
</sub></p>

<p align="center"><sub>
<a href="./SKILL.md">方法论 → SKILL.md</a> &nbsp;·&nbsp;
<a href="../../docs/windows-environment-setup-win11.md">实测记录 → docs/</a>
</sub></p>

---

<p align="right"><sub><a href="../../README.md">← 返回笔记本目录</a> · <a href="./SKILL.md">SKILL.md（AI 执行）</a></sub></p>
