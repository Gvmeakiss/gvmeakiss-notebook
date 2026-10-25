# Windows 审计判据

> 判断一台 Windows 机器当前状态是否正确的客观口径：原则、逐项判据、只读命令。所有判据以回读结果为准，不以开关、状态位或界面显示为准。

---

## 1. 判定原则

### 1.1 命令成功 ≠ 生效

写入类命令返回成功只说明调用完成。`Disable-NetAdapterPowerManagement` 可返回成功而 `AllowComputerToTurnOffDevice` 仍为 `Enabled`。每个修改必须回读同一位置的值。

### 1.2 只看结果，不看开关

注册表值、任务状态 `Ready`、界面打勾都只是开关。判断生效要看功能结果：MMCSS 的注册表值全部正确，但 `sc query MMCSS` 为 `STOPPED` 时，`SystemResponsiveness` 与 `Tasks\Games\*` 全部是死值。

### 1.3 单一表征会误导

服务的实际职责常与显示名不符：`TabletInputService` 的显示名是「触屏键盘」，在 Win10 上还承载输入法语言栏与输入指示器。判断前先确认对象的真实职责与依赖，不用一个状态位代替整条链路。

### 1.4 补丁级别用 UBR，不用 Get-HotFix

`Get-HotFix` 不列累积更新。真实补丁级别看 `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion` 的 `UBR`。`Windows Update` 报「安装成功」但 `UBR` 未上升，等于该累积更新未提交：SSU 装上了、LCU 回滚，更新会被重新提供。

### 1.5 判定口径与取证边界

- 注册表判定必须声明 32/64 位视图：`HKLM\SOFTWARE` 在 32 位进程下重定向到 `WOW6432Node`，同一路径可能「一个有、一个没有」。一律以 64 位视图为准，并与清单写的路径字符串对齐。
- `reg query` 对不存在的键返回 exit 1，不是 0。「查不到」不等于「不存在」，先确认查询手段本身有效。
- 调优值缺失即 FAIL（累积更新以删值方式重置），但报告只写「现在不生效」，不推断删除原因：整键消失与单值被删在取证上不可区分。
- 清单未给期望值的项标「结论不明」，不硬判 PASS / FAIL。

---

## 2. 逐项判据表

| 项 | 正确状态 | 错误但常见 | 怎么验 |
|---|---|---|---|
| 系统文件完整性 | `sfc /verifyonly` 未发现完整性冲突 | 报完整性冲突 | `sfc /verifyonly` |
| 补丁级别 | `UBR` 随最新累积更新提交而上升，与已装 KB 对应 | WU 报「安装成功」但 `UBR` 未上升；更新被反复重新提供 | `reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR` 加 `winver` 对照 |
| 待装更新 | Windows 更新查询 = 0 个待装 | 存在待装更新 | 设置 → Windows 更新 查询 |
| 更新策略 | `WindowsUpdate` 策略键不存在，或存在但不携带阻止值 | `NoAutoUpdate=1`、`SetDisableUXWUAccess=1`，更新被策略接管 | `reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /s` |
| 内核驱动类调优（MMCSS） | 注册表值正确，且 `sc query MMCSS` = `STATE: 4 RUNNING`、`sc qc MMCSS` = `START_TYPE: 2 AUTO_START` | 值全对但 `STATE: STOPPED` / `WIN32_EXIT_CODE=1341`，调优值全部无效 | `sc.exe query MMCSS`、`sc.exe qc MMCSS` |
| 调优值存活 | `SystemProfile`、`Tasks\Games`、`GameDVR` 下目标值存在且等于期望值 | 值缺失；整键或整子树消失（同样记 FAIL） | `reg query` 上述三个路径 |
| 电源方案关键项（最小处理器状态等） | 当前方案的目标项与期望值一致，输出按十六进制核对 | 电源方案被切换，或关键项被改到非期望档位 | `powercfg /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c` |
| SSD / TRIM | `DisableDeleteNotify=0`，磁盘 Healthy | `DisableDeleteNotify=1`（TRIM 关闭） | `fsutil behavior query DisableDeleteNotify` |
| 蓝屏与显卡挂起证据 | `C:\Windows\Minidump` 为空；`C:\Windows\LiveKernelReports` 为空，且无 4101/4102 事件 | 存在 `WATCHDOG\*.dmp`，或出现 4101/4102 事件 | `Get-ChildItem C:\Windows\Minidump`、`Get-ChildItem C:\Windows\LiveKernelReports\WATCHDOG` |
| 设备故障码 | 非 OK 项全部是 `CM_PROB_PHANTOM`（Code 45，历史拔插记录） | Code 43 / Code 31 等真实故障：缺厂商驱动、设备添加失败 | `Get-PnpDevice` 过滤非 OK，读 `ConfigManagerErrorCode` |
| 关键服务 | 输入法、相机、手柄、商店认证、搜索、打印等按需服务保持 `Manual` 或出厂值 | 被设为 `Disabled` | 与基线快照逐项 diff（269 个服务的启动类型与状态）；`sc.exe query <服务名>` |
| 计划任务 | `Ready`，或一次性任务「最近一次运行成功且 `LastTaskResult=0x0`」；受 ACL 保护的 `UpdateOrchestrator` 任务保持 `Disabled` | 系统任务被批量设为 `Disabled`（如 42 个）；一次性任务上次运行失败且 `LastTaskResult≠0x0` | `Get-ScheduledTaskInfo`；查任务 XML 的 `<Enabled>` 与文件 ACL |
| 文件关联 | `UserChoice` 的 `ProgId` 带 `Hash`，其 `shell\open\command` 指向存在的 exe | 指向已删程序，双击文件没反应或报错 | 遍历扩展名查 `UserChoice` → `shell\open\command`（脚本见命令清单） |
| 快捷方式图标 | `IconLocation` 为空路径 + 索引（如 `,0`）属正常，表示沿用目标程序图标 | `IconLocation` 指向不存在的文件或索引越界 | 只对非空路径 `Test-Path`，空路径直接跳过 |
| Defender | 无第三方杀软时实时保护开启；第三方接管时 Defender 实时保护 `False`、其内核驱动在跑、`SecurityCenter2` 注册为启用 | 无第三方接管而实时保护 `False`；第三方已卸载而 Defender 仍关闭 | `Get-MpComputerStatus`；查 `SecurityCenter2` 注册状态与杀软内核驱动 |
| 便携软件 | 清单声明的每个 exe 按相对路径存在，`VersionInfo.FileVersion` 可读 | exe 路径写错、文件缺失，或版本与清单不符 | `Join-Path` 清单相对路径回读（脚本见命令清单） |
| 网卡省电 | `PnPCapabilities = 24 (0x18)`，`AllowComputerToTurnOffDevice = Disabled` | 无线网卡为 `16`、有线网卡未设置；`Disable-NetAdapterPowerManagement` 报成功但值未变 | `Get-NetAdapter -Physical` 加 `Get-NetAdapterPowerManagement` |
| 索引 / 预读 | `WSearch`、`SysMain` 保持 `Running` / `Automatic` 或出厂值 | 被优化脚本设为 `Disabled` | `sc.exe query WSearch`、`sc.exe query SysMain` |

---

## 3. 只读审计命令清单

```powershell
# 系统文件与补丁
sfc /verifyonly
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR

# 蓝屏 / 显卡挂起证据
Get-ChildItem C:\Windows\Minidump
Get-ChildItem C:\Windows\LiveKernelReports\WATCHDOG

# 服务与驱动 / Defender（注册表值对 ≠ 生效）
sc.exe query MMCSS                       # 期望 STATE: 4 RUNNING
sc.exe qc    MMCSS                       # 期望 START_TYPE: 2 AUTO_START
sc.exe query WSearch
sc.exe query SysMain
Get-MpComputerStatus

# 调优值存活（含「被累积更新删掉」的判定：缺失即 FAIL）
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"

# 更新策略（键不存在 = 系统默认，不要只看某个值）
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /s

# 电源：当前方案的关键项（注意十六进制）
powercfg /query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c

# 磁盘 / TRIM
fsutil behavior query DisableDeleteNotify

# 设备故障码
Get-PnpDevice | Where-Object Status -ne 'OK' | Select-Object Status,Class,FriendlyName,ConfigManagerErrorCode

# 计划任务
Get-ScheduledTask | Get-ScheduledTaskInfo | Where-Object { $_.LastTaskResult -ne 0 } | Select-Object TaskName,LastTaskResult

# 便携软件：按清单声明的相对路径核对存在性与文件版本
$apps = '~\Apps'
foreach ($rel in @('JPEGView\JPEGView64\JPEGView.exe','MPC-BE\mpc-be64.exe','MarkText\MarkText.exe','rclone\rclone.exe')) {
    $p = Join-Path $apps $rel
    if (Test-Path -LiteralPath $p) { "{0,-42} {1}" -f $rel, (Get-Item $p).VersionInfo.FileVersion }
    else { "{0,-42} 缺失" -f $rel }
}

# 网卡省电
Get-NetAdapter -Physical | % { Get-NetAdapterPowerManagement -Name $_.Name }

# 文件关联：默认 ProgID 指向的 exe 是否还存在
foreach ($ext in '.md','.png','.mp4') {
    $uc  = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $cls = (Get-ItemProperty "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue).'(default)'
    $progId = if ($uc) { $uc } else { $cls }
    $cmd = (Get-ItemProperty "HKCU:\Software\Classes\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    "{0,-8} {1,-30} {2}" -f $ext, $progId, $cmd
}

# 集合验收（tune 存活检查）
pwsh -File skills/win-ai-gaming-setup/scripts/verify-env.ps1
```
