# 系统优化副作用审计报告

**审计时间**：2026-10-09 凌晨
**审计对象**：`lol-optimize` 系列脚本对系统所做的改动
**审计方式**：与优化前快照（`services-snapshot.csv`，269 个服务）逐项对比 + 悬空引用排查 + 功能可用性验证

---

## 一、已自动修复（2 项）

### 1. 输入法消失 —— 已修复（用户已完成，本次确认）

| 项 | 状态 |
|---|---|
| 根因 | `optimize-round2.ps1` 第 5 步把 `TabletInputService` 设为 **Disabled** |
| 错误理由 | 脚本注释写「触屏键盘 (无触摸屏可关)」——实际该服务在 Win10 上还承载**输入法语言栏与输入指示器** |
| 修复 | `sc config start= demand` + `sc start`（注册表改不够，SCM 有缓存） |
| 当前状态 | ✅ `Manual` / `RUNNING`，`ctfmon` 运行中（PID 5252） |
| 防复发 | 脚本 L114 已注释并写明原因 |

**残留待办**：`HKCU\...\Run` 里有一条 `ctfmon` 自启项（上次排查加的兜底）。
现在服务已是 `Manual`，这条**冗余但无害**。要清理就删它。

### 2. 网卡被"允许关闭以省电" —— 本次已修复

| 项 | 详情 |
|---|---|
| 原脚本意图 | 第 6 步 `Disable-NetAdapterPowerManagement` |
| 实际情况 | **未生效** —— 修复前两个网卡都是 `AllowComputerToTurnOffDevice = Enabled` |
| 为什么没生效 | 脚本用了 `-NoRestart`，而该设置需要重启适配器才应用；脚本也未验证结果 |
| 影响 | **游戏中随机掉线 / 延迟尖峰**（对 LOL 尤其致命） |
| 本次修复 | 官方注册表方式 `PnPCapabilities = 24 (0x18)`，两个网卡均已写入 |
| 生效时机 | **下次重启网卡或系统后**（当前仅靠 WLAN 联网，故未即时重启适配器以免断开会话） |

| 网卡 | 修复前 | 修复后 |
|---|---|---|
| Realtek PCIe GbE Family Controller | (未设置) | **24** |
| MediaTek Wi-Fi 6 MT7921 | 16 | **24** |

> 验证复活命令（重启后跑）：
> `Get-NetAdapter -Physical | % { Get-NetAdapterPowerManagement -Name $_.Name }`
> 应显示 `AllowComputerToTurnOffDevice = Disabled`。

---

## 二、需要你决策（不擅自改）

这些是**有意为之的取舍**，不是故障。原脚本的注释也表明是你选择的结果。但其中两项有真实代价，列出来供你判断。

### A. 微软商店 / Game Pass 认证被切断 ⚠ 有实际影响

`XblAuthManager`（Xbox Live 身份验证）已禁用。它的作用**不只 Xbox**：

| 受影响 | 说明 |
|---|---|
| 微软商店登录 / 购买 | 需要该服务完成认证 |
| Game Pass | 完全依赖 |
| 部分 UWP 游戏 | 依赖 Xbox 网络与云存档 |

同时被禁用的还有 `XblGameSave`（云存档）、`XboxNetApiSvc`（联机）、`XboxGipSvc`（手柄）。

**如果你不用商店/Game Pass/手柄 → 可以保持现状。**
**如果哪天要用 → 恢复方法**：
```powershell
# 管理员
foreach ($s in 'XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc') {
    sc.exe config $s start= demand
}
```

### B. 「设置 → Windows 更新」页面被隐藏 ⚠ 有实际影响

| 策略 | 值 | 影响 |
|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` → `SetDisableUXWUAccess` | `1` | **隐藏更新页面**，无法手动检查更新 |
| 同上 → `AU\NoAutoUpdate` | `1` | 不自动安装安全更新 |

**注意**：这两个**不是** `lol-optimize` 设的 —— 三个脚本都未涉及 Windows Update 策略，
`admin-tweaks` 只关了「更新 P2P 上传」。所以是更早就存在的（或别的工具设的）。

**系统本身并不落后**（这点我最初判断错了，已更正）：

| 指标 | 值 |
|---|---|
| UBR | **3803** |
| KB5066135 | 已安装（2026-10-08） |
| 待重启标记 | 无（CBS/WU 都干净） |

> 教训：`Get-HotFix` **不列累积更新**，只看它会误判系统补丁状态。应以 `UBR`
> （`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`）为准。

**恢复方法**（管理员，若你希望恢复更新入口）：
```powershell
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'SetDisableUXWUAccess' -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
```
或保留 `NoAutoUpdate`（手动控制更新时机）但去掉 `SetDisableUXWUAccess`，
这样你仍能打开更新页面手动装。

### C. UWP 后台驻留被策略级禁止

| 位置 | 值 |
|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy` → `LetAppsRunInBackground` | `2`（强制拒绝） |
| `HKCU\...\BackgroundAccessApplications` → `GlobalUserDisabled` | `1`（并隐藏每应用开关） |

**代价**：UWP 应用无法后台活动 —— 邮件/日历不推送横幅、部分应用启动更慢。
**收益**：省电省内存。
**注**：这是微软在新版 Windows 上的默认行为，属正常取舍。**保持即可**。

### D. 其它已确认无害的禁用

| 服务 | 原始值 | 现状 | 评价 |
|---|---|---|---|
| `RemoteRegistry` | 本来就是 Disabled | Disabled | ✅ 非本次改动 |
| `DiagTrack`（遥测） | 本来就 Disabled | Disabled | ✅ 非本次改动 |
| `SysMain` | 本来就 Disabled | Disabled | ✅ 非本次改动 |
| `SEMgrSvc`（NFC 支付） | Manual | Disabled | 台式机无用，合理 |
| `stisvc`（图像采集）⚠ | **Auto** | Disabled | 无扫描仪/相机则合理；**基线是 Auto**，若以后接扫描仪需恢复 |
| `WMPNetworkSvc` | Manual | Disabled | 无 WMP 网络共享则合理 |
| `Fax` / `RetailDemo` | Manual | Disabled | 安全 |

> 想恢复某一个：`sc.exe config <服务名> start= demand`（或 `auto`），管理员权限。

---

## 三、排查结论：无其它故障

| 检查项 | 结果 |
|---|---|
| **悬空服务引用**（服务指向不存在的 exe） | ✅ 无 |
| **悬空任务引用**（计划任务指向不存在的程序） | ✅ 无 |
| 音频（`Audiosrv` / `AudioEndpointBuilder`） | ✅ Auto / Running |
| 网络（`Dnscache` / `Dhcp`） | ✅ Auto / Running |
| Windows 搜索 | ✅ Manual / Running |
| 打印后台 | ✅ Auto / Running |
| 主题服务 | ✅ Auto / Running |
| Windows 更新服务 | ✅ Manual / Running（策略层被限制，服务本身正常） |
| Defender | ⚠ Stopped —— **但这是正常的**：火绒安全软件在运行（状态码 `0x41000`），第三方杀软接管时 Defender 自动让位 |
| IFEO 映像劫持 | ✅ 无针对 `ctfmon` 的劫持 |
| 输入法文件 | ✅ `System32\InputMethod\CHS` 完整（10 个文件） |
| 语言与键盘布局注册 | ✅ `zh-Hans-CN en-US`、`00000804` 已预加载、微软拼音为选中 IME |

---

## 四、本次审计的方法论沉淀

### 逐项对比快照，而不是"看哪里可疑"

优化前拍照（269 个服务的启动类型与状态），优化后逐项 diff。这直接定位了
`TabletInputService` 从 `Manual` 变成 `Disabled`。

**并且要区分"你改的"与"本来就那样"**：`RemoteRegistry` / `DiagTrack` / `SysMain`
在基线里就是 Disabled —— 如果把它们算成自己的"加固成果"，就会在恢复时误把它们打开。

### 命令报成功 ≠ 设置生效

网卡省电就是活例：`Disable-NetAdapterPowerManagement` 返回成功，
`AllowComputerToTurnOffDevice` 仍是 `Enabled`。**每个修改都必须回读验证。**

### 用 UBR 判断补丁状态，不要用 `Get-HotFix`

`Get-HotFix` 不列累积更新，会得出"系统停在 2023-12"的错误结论。
正确指标是 `UBR`（当前 3803）。

### 单一表征会误导

"输入法消失"看起来像输入法本身的问题，实际是 `TabletInputService` 被禁。
**服务的实际职责常与其显示名不符** —— 这是 `optimize-round2.ps1` 判断错误的根本原因。

---

## 五、清单汇总

| # | 项目 | 状态 |
|---|---|---|
| 1 | 输入法消失 | ✅ 已修复（确认正常） |
| 2 | 网卡省电导致掉线风险 | ✅ 已修复（重启后生效） |
| 3 | 微软商店 / Game Pass 认证 | ⚠ 待你决策 |
| 4 | 更新页面被隐藏 | ⚠ 待你决策 |
| 5 | UWP 后台驻留 | 保留（合理取舍） |
| 6 | 其它服务禁用 | 保留（合理取舍） |
| 7 | 悬空引用 / 其它功能 | ✅ 无问题 |
