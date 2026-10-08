# Windows 系统调优安全：先拍照，再动手，出问题能回滚

系统"优化"脚本（关服务、改注册表、清后台）会带来**看起来完全无关**的故障。
本目录提供一套闭环：**调优前快照 → 调优后对比 → 按快照回滚**，外加一个针对
"输入法消失"这类高频故障的诊断修复工具。

来自一次真实事故：一台 Windows 10 机器，优化脚本把 `TabletInputService` 设为禁用，
重启后微软拼音消失、`Win+Space` 无反应、`ctfmon.exe` 启动即退出。
脚本注释写的理由是「触屏键盘（无触摸屏可关）」—— **这个理由本身就是错的**。

---

## 核心问题：服务的显示名不等于它的职责

这是所有此类故障的根源。

| 服务（显示名） | 你以为它只做 | 它实际还做 |
|---|---|---|
| **TabletInputService**<br>"Touch Keyboard and Handwriting Panel Service" | 触屏键盘 | **输入法语言栏 + 输入指示器**。禁掉 → 输入法消失 |
| XblAuthManager<br>"Xbox Live Auth Manager" | Xbox | **微软商店登录/购买、Game Pass 认证** |
| XblGameSave | Xbox 云存档 | 许多非 Xbox 游戏的云存档 |
| Windows Search (`WSearch`) | 搜索索引 | 开始菜单文件搜索、资源管理器搜索 |
| Themes | 主题 | 整个视觉样式；禁掉退回经典外观 |
| BITS | 后台传输 | Windows 更新、商店下载、部分安装器 |

**结论：不要按显示名判断一个服务能否禁用。** 要么查依赖，要么先拍照再动手。

---

## 脚本

### `scripts/snapshot-services.ps1` — 调优前拍照（只读）

```powershell
pwsh -File scripts/snapshot-services.ps1
pwsh -File scripts/snapshot-services.ps1 -OutDir C:\backup\before-tweak
```

采集到一个目录：

| 内容 | 形式 |
|---|---|
| 服务（名称 / 启动类型 / 状态） | `services-snapshot.csv` |
| 自启项（Run / RunOnce，各 hive） | `Run-*.reg`（可 `reg import` 还原） |
| 计划任务（路径 / 名称 / 状态） | `tasks-snapshot.csv` |
| 电源方案、视觉效果、**IME 状态**、后台应用策略 | `misc-state.txt` |

**这一步是整套方法的地基。** 没有基线，事后无法证明某个设置是优化改的还是本来就这样。

### `scripts/compare-services.ps1` — 调优后对比 + 回滚

```powershell
pwsh -File scripts/compare-services.ps1 -Snapshot ..\services-snapshot.csv
pwsh -File scripts/compare-services.ps1 -Snapshot ..\services-snapshot.csv -Restore -WhatIf
pwsh -File scripts/compare-services.ps1 -Snapshot ..\services-snapshot.csv -Restore -Only TabletInputService
```

报告四组：

1. **启动类型偏离基线的服务** ← 真正被改动的
2. **watchlist 中被禁用的服务**，并区分：
   - (a) **优化改的** ← 要审的重点
   - (b) **基线本来就禁用** ← 不是你的功劳，别盲目"修复"
3. 基线本来就禁用的全部服务
4. 现在运行但基线是停止的服务

`-Restore` 用 `sc config` 写回基线（需管理员）。

### `scripts/diagnose-ime.ps1` — 输入法故障诊断/修复

```powershell
pwsh -File scripts/diagnose-ime.ps1
pwsh -File scripts/diagnose-ime.ps1 -Repair     # 需管理员
```

检查：服务状态、`ctfmon`/`TextInputHost` 进程（`ctfmon` 起不来时会**捕获退出码**）、
语言与键盘布局注册、语言栏模式、IFEO 劫持、后台应用策略、杀软干扰。

---

## 三个关键机理（都经实测）

### 1. 改服务启动类型：注册表不够，必须走 SCM

实测：直接改注册表里服务的 `Start` 值**不生效** —— 服务控制管理器（SCM）缓存了自己的副本。
必须用 `sc config` 通知它，再 `sc start`：

```powershell
sc.exe config TabletInputService start= demand   # 3 = Manual
sc.exe start  TabletInputService
```

> 注意 `start=` 后面**必须有个空格**，这是 `sc.exe` 的语法要求。

### 2. 命令报成功 ≠ 设置生效

真实案例：`Disable-NetAdapterPowerManagement -Name X` **返回成功**，
但 `AllowComputerToTurnOffDevice` 始终是 `Enabled`。原因是脚本用了 `-NoRestart`，
而该设置需要重启适配器才应用；脚本也没回读验证。

**规则：每个修改之后都要回读验证。** 报 success 只说明命令被接受。

### 3. 断掉的输入法会话：重启才能恢复

细节：`TabletInputService` 恢复为 Manual 并启动后，**坏掉的登录会话里 `ctfmon` 仍起不来**
（退出码 1）。必须重启重建输入栈。

所以修复流程是：**改服务 → 重启 → 再验证**，不要在同一会话里反复尝试拉起 `ctfmon`。

---

## 更新检测：别用 `Get-HotFix` 判断补丁状态

`Get-HotFix` **不列累积更新**，只看它会得出严重错误的结论。

**实测对比**（同一台机器）：

| 方法 | 结论 |
|---|---|
| `Get-HotFix` 最新一条 | KB5015684，**2023-12** ← 错误，以为落后两年 |
| `UBR` + `Get-HotFix` 全量 | UBR **3803**，KB5066135 已装（2026-10） ← 真实，系统是新的 |

正确读法：

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object DisplayVersion, CurrentBuild, UBR
```

---

## 常见"优化"项的真实代价

供决策参考，不是一律反对 —— 但要知道代价：

| 优化项 | 代价 | 建议 |
|---|---|---|
| 禁用 `TabletInputService` | **输入法消失** | ❌ 绝不要做 |
| 禁用 `XblAuthManager` 等 | 商店登录/购买、Game Pass 失效 | ⚠ 确认不用再做 |
| 禁用 `stisvc` | 扫描仪/相机失效（基线常是 Auto） | ⚠ 按需 |
| 禁用 `WSearch` | 开始菜单文件搜索失效 | ⚠ 很少值得 |
| 禁用 `Spooler` | 完全无法打印 | ⚠ 确认不用打印机 |
| `LetAppsRunInBackground = 2` | UWP 不推送通知、部分应用变慢 | ✅ 常见取舍，可接受 |
| `SetDisableUXWUAccess = 1` | **隐藏「设置 → Windows 更新」** | ⚠ 想看更新就别设 |
| `NoAutoUpdate = 1` | 不自动装安全更新 | ⚠ 安全取舍 |
| 网卡 `PnPCapabilities = 24` | 无（纯粹防止掉线） | ✅ 推荐 |
| 禁用遥测 `DiagTrack` | 无 | ✅ 推荐，且基线常已禁用 |
| 禁用 `RemoteRegistry` | 无 | ✅ 多数基线已禁用 |

### 关于 `Get-HotFix` 与 `RemoteRegistry` 的一个陷阱

**先看基线再声称"加固成果"。** `RemoteRegistry`、`DiagTrack`、`SysMain`
在很多机器上**出厂就是 Disabled**。把它们算成自己的成绩，回滚时就会误把它们打开。

---

## 网卡省电：正确做法

`Disable-NetAdapterPowerManagement` 在部分驱动上不生效。官方文档的注册表方式更可靠：

```powershell
# 0x18 = 24 = 禁用网卡电源管理
$cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
Get-ChildItem $cls | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p.DriverDesc -and $p.DriverDesc -notmatch 'WAN Miniport|Kernel Debug') {
        Set-ItemProperty $_.PSPath -Name 'PnPCapabilities' -Value 24 -Type DWord
    }
}
```

**生效需要重启网卡或系统。** 若当前只靠某个适配器联网（例如只有 WLAN 连着），
**不要即时重启它** —— 会切断你自己的会话。写入后下次重启生效即可。

验证：
```powershell
Get-NetAdapter -Physical | ForEach-Object { Get-NetAdapterPowerManagement -Name $_.Name }
# 期望 AllowComputerToTurnOffDevice = Disabled
```

---

## 工作流程

```powershell
# 1) 动手之前 —— 拍照
pwsh -File scripts/snapshot-services.ps1 -OutDir C:\backup\before-tweak

# 2) 跑你的优化脚本

# 3) 重启（很多改动需要重启才暴露问题）

# 4) 对比：哪些被改了、哪些有风险
pwsh -File scripts/compare-services.ps1 -Snapshot C:\backup\before-tweak\services-snapshot.csv

# 5) 有故障就诊断
pwsh -File scripts/diagnose-ime.ps1          # 输入法类
pwsh -File scripts/compare-services.ps1 -Snapshot ... -Restore -WhatIf   # 准备回滚

# 6) 回滚后重启，再验证
```

---

## 边界

| 限制 | 说明 |
|---|---|
| `-Restore` 与 `-Repair` 需要管理员 | 改服务启动类型是机器级操作 |
| 部分改动需重启才生效 | 输入法栈、网卡电源管理都属于此类 |
| 脚本不改你的取舍 | 是否有意禁用某服务，只有你知道；脚本只把事实摆出来 |
| 快照不是完整系统备份 | 只覆盖本脚本列出的项（服务/自启/任务/电源/IME） |

---

## 安全纪律

- **快照目录里含自启项导出**（`Run-*.reg`），可能包含本机路径信息；
  它是本地恢复用的，不要提交到公开仓库
- 优化脚本与其日志可能含主机名、用户名、内网地址 —— 入库前脱敏
- 回滚前先 `-WhatIf` 干跑，确认要改的项与预期一致
