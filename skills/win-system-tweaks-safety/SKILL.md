---
name: win-system-tweaks-safety
description: 安全地做 Windows 系统调优，并在优化脚本造成故障后诊断与回滚。当出现"系统优化后输入法不见了""打不出中文了""Win+空格没反应""某个功能优化后坏了""服务被禁用了怎么恢复""优化脚本改了哪些东西""想关服务但不知道有什么后果""游戏里随机掉线"等诉求时使用。核心是三条：服务的显示名不等于它的职责（TabletInputService 禁掉会毁掉输入法）、命令报成功不等于设置生效（必须回读验证）、调优前必须先拍快照否则事后无法区分"你改的"与"本来就这样"。
agent_created: true
---

# Windows 系统调优安全

## 适用场景

- "优化之后输入法不见了 / 打不出中文 / `Win+空格` 没反应"
- "我关了些服务，现在某个功能坏了，怎么恢复"
- "这个优化脚本改了哪些东西？" / "优化前是什么状态？"
- "想关服务/改注册表，但怕搞坏系统"
- "游戏里随机掉线 / 延迟尖峰"

**这类故障的共同特征是症状与原因看起来毫无关系。** 输入法消失的根因是
`TabletInputService` 被禁 —— 而它的显示名是「触屏键盘和手写面板服务」。

## 第一原则：先拍照，再动手

**没有基线的优化是不可回滚的。** 而且事后你无法回答一个关键问题：
*这个设置是我改的，还是本来就这样？*

```powershell
pwsh -File scripts/snapshot-services.ps1 -OutDir C:\backup\before-tweak
```

采集服务启动类型/状态、自启项、计划任务、电源方案、IME 状态、后台应用策略。
**只读，不改任何东西。**

## 第二原则：服务的显示名 ≠ 它的职责

所有此类故障的根源。这张表是本 Skill 最有价值的部分：

| 服务 | 显示名让你以为 | 实际还负责 |
|---|---|---|
| **`TabletInputService`** | 触屏键盘 | **输入法语言栏 + 输入指示器**。禁掉 → 输入法消失、`ctfmon` 起不来 |
| `XblAuthManager` | Xbox Live | **微软商店登录/购买、Game Pass 认证** |
| `XblGameSave` | Xbox 云存档 | 许多非 Xbox 游戏的云存档 |
| `XblGameSave` / `XboxNetApiSvc` | Xbox 联机 | 部分商店游戏的多人功能 |
| `WSearch` / `Windows Search` | 搜索索引 | 开始菜单文件搜索、资源管理器搜索 |
| `Themes` | 主题 | 整个视觉样式 |
| `BITS` | 后台传输 | Windows 更新、商店下载、部分安装器 |
| `Spooler` | 打印后台 | 所有打印能力 |
| `stisvc` | 图像采集 | 扫描仪、相机（**基线常是 Auto**） |

**因此：不要按显示名决定禁用。** 要么查依赖关系，要么先拍照、后验证。

## 第三原则：命令报成功 ≠ 设置生效

真实案例：`Disable-NetAdapterPowerManagement -Name X` **返回成功**，
但 `AllowComputerToTurnOffDevice` 依然是 `Enabled` —— 因为它被配了 `-NoRestart`，
而该设置需要重启适配器才应用。

**每个修改之后都要回读验证。**

## 工作流程

### 第一步：调优前拍照

```powershell
pwsh -File scripts/snapshot-services.ps1 -OutDir C:\backup\before-tweak
```

### 第二步：调优，然后**重启**

很多改动（服务启动类型、网卡电源管理、输入法栈）**必须重启才暴露问题**。
不重启就当成功，是最常见的错判。

### 第三步：对比，找出真正被改的项

```powershell
pwsh -File scripts/compare-services.ps1 -Snapshot C:\backup\before-tweak\services-snapshot.csv
```

报告分四组，**关键是要区分**：

| 组 | 含义 |
|---|---|
| 启动类型偏离基线 | 真正被改动的 ← 审这里 |
| watchlist 被禁用 · (a) 优化改的 | **要重点审的** |
| watchlist 被禁用 · (b) 基线本来就禁用的 | **不是你的功劳，别盲目"修复"** |
| 基线本就禁用的全部服务 | 判断"加固成果"的依据 |

> 陷阱：`RemoteRegistry`、`DiagTrack`、`SysMain` 在很多机器上**出厂就是 Disabled**。
> 把它们当成自己的加固成果，回滚时就会误把它们打开。

### 第四步：出故障就诊断

```powershell
pwsh -File scripts/diagnose-ime.ps1        # 输入法类故障
pwsh -File scripts/diagnose-ime.ps1 -Repair   # 需管理员
```

诊断会检查服务状态、`ctfmon`/`TextInputHost` 进程（**`ctfmon` 起不来时捕获退出码**）、
语言与键盘布局注册、语言栏模式、IFEO 劫持、后台应用策略、杀软干扰，并给出**结论**而非罗列。

### 第五步：回滚

```powershell
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore
```

## 输入法故障：完整修复路径

这是最高频的一类，单独说清。

### 症状
重启后中文打不出来；`Win+空格` 无反应；任务栏输入指示器消失；`ctfmon.exe` 启动即退出。

### 诊断
```powershell
pwsh -File scripts/diagnose-ime.ps1
```
若报 `TabletInputService is DISABLED` —— 就是它。

### 修复（管理员）
```powershell
sc.exe config TabletInputService start= demand
sc.exe start  TabletInputService
```
**注意 `start=` 后必须有空格**（`sc.exe` 语法要求）。

### 关键：改注册表不够

实测：直接改注册表里服务的 `Start` 值**不生效** —— 服务控制管理器（SCM）
缓存了自己的副本。必须用 `sc config`（`ChangeServiceConfig`）通知它。

### 关键：必须重启

**坏掉的登录会话里 `ctfmon` 无论如何都起不来**（退出码 1）。
服务修好后仍需**重启**重建输入栈。不要在同一会话里反复尝试拉起 `ctfmon`。

### 防复发
把优化脚本里那条禁用项**注释掉并写明原因**，否则重跑会再次踩坑。

## 更新检测：别用 `Get-HotFix`

`Get-HotFix` **不列累积更新**，只看它会得出严重错误的结论。同一台机器的实测对比：

| 方法 | 结论 |
|---|---|
| `Get-HotFix` 最新一条 | KB5015684，2023-12 ← **错误**，以为落后两年 |
| `UBR` | **3803**，KB5066135 已装 ← 正确，系统是新的 |

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object DisplayVersion, CurrentBuild, UBR
```

## 网卡省电：正确做法

`Disable-NetAdapterPowerManagement` 在部分驱动上不生效。用官方文档的注册表值：

```powershell
Set-ItemProperty "$cls\$sub" -Name 'PnPCapabilities' -Value 24 -Type DWord   # 0x18
```

**生效需重启适配器或系统。** 若当前只靠该适配器联网（例如只有 WLAN 连着），
**不要即时重启它** —— 会切断你自己的会话。

## 常见"优化"项的真实代价

| 项 | 代价 | 建议 |
|---|---|---|
| 禁 `TabletInputService` | **输入法消失** | ❌ 绝不要做 |
| 禁 `XblAuthManager` 等 | 商店登录/购买、Game Pass 失效 | ⚠ 确认不用再做 |
| 禁 `WSearch` | 文件搜索失效 | ⚠ 很少值得 |
| 禁 `Spooler` | 无法打印 | ⚠ 确认不用打印机 |
| `LetAppsRunInBackground = 2` | UWP 不推通知、启动变慢 | ✅ 常见取舍 |
| `SetDisableUXWUAccess = 1` | **隐藏「设置 → Windows 更新」** | ⚠ 想看更新就别设 |
| `NoAutoUpdate = 1` | 不自动装安全更新 | ⚠ 安全取舍 |
| 网卡 `PnPCapabilities = 24` | 无，纯防掉线 | ✅ 推荐 |
| 禁 `DiagTrack` / `RemoteRegistry` | 无 | ✅ 但常是基线默认 |

## 边界

| 限制 | 说明 |
|---|---|
| `-Restore` / `-Repair` 需管理员 | 改服务启动类型是机器级操作 |
| 部分改动需重启生效 | 输入法栈、网卡电源管理均属此类 |
| **脚本不替你决定取舍** | 某服务是否该禁只有你知道；脚本只把事实与代价摆出来 |
| 快照≠完整系统备份 | 只覆盖服务/自启/任务/电源/IME |

## 安全纪律

- 快照目录含自启项导出（`Run-*.reg`），可能有本机路径信息，**不要提交到公开仓库**
- 优化脚本与日志常含主机名、用户名、内网地址 —— 入库前脱敏
- 回滚前先 `-WhatIf` 干跑，确认改动项与预期一致
