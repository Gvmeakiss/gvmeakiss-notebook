# 系统调优清单

本文是 [win-ai-gaming-setup](../skills/win-ai-gaming-setup/SKILL.md) 中 `tune` 阶段的**状态规范**：一台调优完成的机器上，下面每一项都应当为真。它不叙述改了什么、哪次改的，只回答三件事——正确值是什么、凭什么、怎么验。

注册表写入由 `setup.ps1 -Phase tune` 完成，验收由 `verify-env.ps1` 完成，两者描述的是同一批值：**不一致就是缺陷**，见文末「维护约束」。

<details>
<summary><b>本页目录</b>（12 节）</summary>

- [使用方式](#使用方式)
- [游戏响应](#游戏响应)
- [广告与推荐](#广告与推荐)
- [搜索](#搜索)
- [遥测与出网](#遥测与出网)
- [安全兜底与可回滚](#安全兜底与可回滚)
- [磁盘与界面](#磁盘与界面)
- [后台与锁屏](#后台与锁屏)
- [隐私面](#隐私面)
- [游戏模式与界面](#游戏模式与界面)
- [手工项](#手工项)
- [维护约束](#维护约束)

</details>

## 使用方式

`-Phase tune` 需要管理员权限，且必须在**交互用户**会话里运行：SYSTEM 身份下 `HKCU` 指向 SYSTEM 的 hive，用户作用域的写入会落错配置单元，脚本会直接拒绝执行。

```powershell
# 仓库根目录执行
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase tune   # 写入
pwsh -File skills/win-ai-gaming-setup/scripts/verify-env.ps1          # 验收：看 --- tune tweaks 段
```

- **怎么读**：每行三列。第一列 = 项 + 正确值（注册表路径照抄代码）+ 落地方式；`可脚本化 · -Phase tune` 表示由 tune 写入，`需手工` 的项全部集中在「手工项」。
- **本表规模**：48 行 = 42 个值行 + 6 个状态项（MMCSS 驱动、7 个遥测任务、DiagTrack 防火墙组、还原点、服务快照、撤销脚本），共覆盖 43 个注册表值（两个活动策略值合写在一行）。43 个值里 42 个有逐值检查、1 个（`EnablePeriodicBackup`）改查结果——**没有「写了但没人查」的值**，tweaks 组共 49 条检查。
- **写入机制**：所有非 opt-in 项合并成一个 `.reg`，一次 `reg import` 导入（合并进已有键，不重建键），随后逐值回读；没落盘的值退化为 `Set-ItemProperty` 直写再回读。命令返回成功不算证据，**回读到的值才算**。
- **判定口径**：值**缺失算 FAIL**（累积更新是删值，不是改值）；比的是**值**不是存在性；`0xffffffff`、`-1`、`4294967295` 是同一个 DWORD；字符串型逐字比对（`High` 不是 `high`）；标 Optional 的检查只报 INFO 不报 FAIL。
- **边界**：默认状态不含 opt-in 开关（鼠标加速、高性能电源方案、关睡眠），也不含禁用服务、改 UAC、改 DPI、改更新策略——这是刻意的负空间，理由见 [02-decisions.md](./02-decisions.md)。

## 游戏响应

8 个值 + 1 个前置条件；前置条件不成立时，MMCSS 那几个值全部无效。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **AllowGameDVR = 0**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR`<br>可脚本化 · `-Phase tune` | GameDVR 的后台录制持续占用 GPU 与编码器，代价是帧率；策略层对整个机器生效。 | `$tweaks` → **GameDVR policy**，期望 `0`；值缺失即 FAIL。 |
| **GameDVR_Enabled = 0**<br>`HKCU:\System\GameConfigStore`<br>可脚本化 · `-Phase tune` | 同一个开关的用户作用域；策略层与用户层在验收表里各算一条，只落一层就会留下一条 FAIL。 | `$tweaks` → **GameDVR user**，期望 `0`。 |
| **SystemResponsiveness = 10**<br>`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile`<br>可脚本化 · `-Phase tune` | MMCSS 的 CPU 保留百分比，默认 20；10 把更多 CPU 让给游戏线程。注意「更小」不等于「更强」：不可被 10 整除的取值会取整，小于 10 的一律 clamp 回 20，所以 0/1 是 no-op，10 才是能被接受的最小档。 | `$tweaks` → **MMCSS responsiveness**，期望 `10`。 |
| **NetworkThrottlingIndex = 0xffffffff**<br>同一键<br>可脚本化 · `-Phase tune` | 全 1 = 关掉 MMCSS 对网络收发的节流配额，游戏时不再被限流。 | `$tweaks` → **MMCSS net throttling**，期望 `4294967295`（无符号十进制；`0xffffffff`、`-1` 是同一个值）。 |
| **GPU Priority = 8**<br>`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games`<br>可脚本化 · `-Phase tune` | Games 任务类的 GPU 优先级档位。验收会查这一项，所以 tune 必须写——漏写会让验收在每台机器上永久 FAIL。 | `$tweaks` → **MMCSS GPU priority**，期望 `8`。 |
| **Priority = 6**<br>同上键<br>可脚本化 · `-Phase tune` | 同一个任务类的 CPU 优先级。 | `$tweaks` → **MMCSS game priority**，期望 `6`。 |
| **Scheduling Category = 'High'**（REG_SZ）<br>同上键<br>可脚本化 · `-Phase tune` | 任务进哪个 MMCSS 调度类别；字符串型值，不是 DWORD，必须逐字 `High`。 | `$tweaks` → **MMCSS sched category**，期望 `High`。 |
| **SFIO Priority = 'High'**（REG_SZ）<br>同上键<br>可脚本化 · `-Phase tune` | 游戏任务类的存储 IO 优先级；同样是字符串。 | `$tweaks` → **MMCSS sfio priority**，期望 `High`。 |
| **MMCSS 驱动 = RUNNING**<br>`sc.exe query MMCSS`<br>可脚本化 · `-Phase tune`（`sc.exe config MMCSS start= auto` + `sc.exe start MMCSS`） | MMCSS 是内核驱动，`SystemProfile` / `Tasks\Games` 下的 6 个值只在它 RUNNING 时生效，注册表看起来完全正确也可以是死的。实测装显卡驱动后它会停在 STOPPED，且无法按需启动（先是 `StartService failed 2`，后是 1341），只能重启恢复——遇到就重启后重试，不要判定它坏了。 | `$tweaks` → **MMCSS driver running**：`sc.exe query MMCSS` 输出含 `RUNNING`；STOPPED 时上面的值一律视为未生效。 |

最后一行是状态而不是值：MMCSS 那 6 行是否真的在起作用由它决定，GameDVR 两行不受影响。

## 广告与推荐

总闸在策略层（`CloudContent`），其余是用户作用域的分项开关。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **DisableWindowsConsumerFeatures = 1**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent`<br>可脚本化 · `-Phase tune` | 策略层总闸：阻止静默安装应用与推广应用（消费级功能）。 | `$tweaks` → **consumer features off**，期望 `1`。 |
| **SilentInstalledAppsEnabled = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`<br>可脚本化 · `-Phase tune` | 不再静默安装 Store 应用。 | `$tweaks` → **silent app installs**，期望 `0`。 |
| **SystemPaneSuggestionsEnabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 开始菜单不显示应用建议。 | `$tweaks` → **start suggestions**，期望 `0`。 |
| **SubscribedContent-338388Enabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 开始菜单的推荐内容位。 | `$tweaks` → **start recommendations off**，期望 `0`。 |
| **SubscribedContent-338389Enabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | Windows 欢迎体验里的建议位。 | `$tweaks` → **welcome suggestions off**，期望 `0`。 |
| **SubscribedContent-353698Enabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 时间线的建议位。 | `$tweaks` → **timeline suggestions off**，期望 `0`。 |
| **SubscribedContent-310093Enabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 「更新后有什么新功能」的欢迎屏；与 338388 / 338389 / 353698 是**不同的活动 ID**，少写一个就还会弹。 | `$tweaks` → **welcome splash off**，期望 `0`。 |
| **SoftLandingEnabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | Windows 提示（tips）弹窗。 | `$tweaks` → **soft landing tips**，期望 `0`。 |
| **RotatingLockScreenOverlayEnabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 锁屏上的推广浮层。 | `$tweaks` → **lock screen overlay off**，期望 `0`。 |
| **PreInstalledAppsEnabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 预装应用的推广位。 | `$tweaks` → **preinstalled promo off**，期望 `0`。 |
| **OemPreInstalledAppsEnabled = 0**<br>同上键<br>可脚本化 · `-Phase tune` | OEM 预装应用的推广位。 | `$tweaks` → **oem promo off**，期望 `0`。 |
| **ShowSyncProviderNotifications = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`<br>可脚本化 · `-Phase tune` | 资源管理器里的「同步你的设置」广告。 | `$tweaks` → **explorer sync ads**，期望 `0`。 |

12 项全部有逐值检查；同一键一次回读可全部核对：`Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'`。这个键在 Win11 26xxx 上实测会被 `reg import` 静默跳过（连全新值名也不落盘），tune 因此保留逐值直写的兜底——回读到值才算数。

## 搜索

两个策略值落在同一个 HKLM 键上。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **DisableSearchBoxSuggestions = 1**<br>`HKCU:\Software\Policies\Microsoft\Windows\Explorer`<br>可脚本化 · `-Phase tune` | 开始菜单搜索不再给网络建议。用策略键而不是 `HKCU:\Software\Microsoft\Windows\CurrentVersion\Search` 的 `BingSearchEnabled` / `CortanaConsent`：后者在 Win11 24H2+ 上被内核级拒写（报「Not all data was successfully written to the registry」，而该键 ACL 仍显示用户 FullControl），策略键是官方路径，且优先级高于用户作用域。 | `$tweaks` → **bing web search**，接受两条路线：本策略值 = `1`，或 `BingSearchEnabled = 0`。 |
| **ConnectedSearchUseWeb = 0**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search`<br>可脚本化 · `-Phase tune` | 机器级：开始搜索不返回网络结果。 | `$tweaks` → **web search policy**，期望 `0`。 |
| **AllowCortana = 0**<br>同上键<br>可脚本化 · `-Phase tune` | 关掉云端搜索的同意项。 | `$tweaks` → **cortana consent off**，期望 `0`。 |

一次 `Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'` 可同时核对 `ConnectedSearchUseWeb` 与 `AllowCortana`。

## 遥测与出网

关的是上报通道与触发任务，不是服务本身；DiagTrack 服务保持系统默认启动类型——本项目不禁用任何服务。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **AllowTelemetry = 0（企业版 / 教育版 / Server）或 1（其余 SKU）**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection`<br>可脚本化 · `-Phase tune`（按 `EditionID` 判定） | `0`（Security/Off）只在企业版 / 教育版 / Server 上被承认；家庭版与专业版会静默忽略，写着 0 也只是看起来赢了（实测 Win11 Pro 上 `AllowTelemetry=0` 存在、诊断仍然上传）。所以正确值是**按 SKU 判定**出来的，不是一律 0。 | `$tweaks` → **telemetry policy**：`Want` 用与 tune 同一套 `EditionID` 判定（`Enterprise` / `Education` / `Server` 之一则为 `0`，否则 `1`）；值缺失即 FAIL。 |
| **7 个遥测任务全部 = Disabled**<br>`\Microsoft\Windows\Application Experience`：Microsoft Compatibility Appraiser / ProgramDataUpdater / StartupAppTask；`\Microsoft\Windows\Customer Experience Improvement Program`：Consolidator / UsbCeip；`\Microsoft\Windows\DiskDiagnostic`：Microsoft-Windows-DiskDiagnosticDataCollector；`\Microsoft\Windows\Autochk`：Proxy<br>可脚本化 · `-Phase tune` | 兼容性评估、CEIP、USB CEIP、磁盘诊断数据收集、Proxy 采集都挂在这些任务上。清单随 build 变化（实测某 build 上 `Microsoft Compatibility Appraiser` 与 `ProgramDataUpdater` 已不存在），所以正确状态是「**本机存在的都 Disabled**」，而不是「7 个都在」。 | `$tweaks` → **telemetry tasks**（Optional）：存在的任务 `State` 必须全为 `Disabled`；一个任务都不存在也算通过并注明。 |
| **DiagTrack 防火墙组：每条规则 Enabled=True + Action=Block**<br>`Get-NetFirewallRule -Group 'DiagTrack'`<br>可脚本化 · `-Phase tune` | 按组的出站规则封上报通道，而不是删规则：组可以一条命令翻回 Allow，删掉的规则无法复原。 | `$tweaks` → **diagtrack firewall**（Optional）：`Action=Block` 且 `Enabled=True` 的条数 = 组内总数；组不存在也算通过。 |
| **DODownloadMode = 1**<br>`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config`<br>可脚本化 · `-Phase tune` | 传递优化留在局域网内，不向互联网上传。 | `$tweaks` → **delivery optimization**，期望 `1`。 |

## 安全兜底与可回滚

五项写入 + 三个机制。机制不产生「值」，但没有它们，上面所有写入都没有撤销路径。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **至少一个系统还原点**<br>`Get-ComputerRestorePoint`<br>可脚本化 · `-Phase tune` | 注册表写入唯一保证可用的粗粒度回滚。`SystemRestorePointCreationFrequency` 默认 1440 分钟，会把 24 小时内的第二次建点**静默去重**（「建了」其实是假的），所以 tune 临时置 0、建完恢复原值。还原点跟着卷走：换盘或系统重置会清零（实测克隆后 0 个）。 | `verify-env.ps1` → **restore point**（Optional）：计数 > 0；tune 自己也会 `Get-ComputerRestorePoint` 回读一次。 |
| **服务基线快照存在，且没有漂移**<br>`<Destination>\_backup\services-snapshot.csv`<br>可脚本化 · `-Phase tune` | 快照**不是**回滚路径（它记录服务状态，不是机器），用途是区分「被改过的」与「本来就那样」；verify 阶段的 drift 检查靠它，缺快照时这一项会被跳过而不是报错。 | `setup.ps1 -Phase verify` 调 `compare-services.ps1 -Snapshot <快照>\services-snapshot.csv`；无新增漂移即通过。 |
| **PreventDeviceEncryption = 1**<br>`HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker`<br>可脚本化 · `-Phase tune` | 只阻止**未来**的自动设备加密，已经加密的卷不动。自动加密会把恢复密钥绑到账户，重装或换主板后可能锁盘。 | `$tweaks` → **bitlocker auto-encrypt**，期望 `1`。 |
| **EnablePeriodicBackup = 1 + RegIdleBackup 已启用；结果看 `C:\Windows\System32\config\RegBack` > 1 MB**<br>`HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager`<br>可脚本化 · `-Phase tune` | 开关只是「允许周期性 hive 备份」，不等于备份存在：Win11 26xxx 上 `RegIdleBackup` 是无触发器、无动作的空壳，SIT 服务已消失，启用后 RegBack 仍是 0 字节；两天两次重启后才出现 110 MB。所以正确状态以**结果**为准，填充之前靠还原点。 | 开关回读 `EnablePeriodicBackup = 1`、任务 `State` 不是 `Disabled`；`$tweaks` → **registry hive backup**（Optional）：RegBack 总字节 > 1 MB 才算通过，否则报「尚未填充」。 |
| **BackupCount = 2**<br>同上键<br>可脚本化 · `-Phase tune` | 只与 `EnablePeriodicBackup` 配合才有意义：它决定保留几代 hive 备份。默认只留一代，覆盖之后就没有可比对的上一份。 | `$tweaks` → **registry backup depth**，期望 `2`。 |
| **DisableWpbtExecution = 1**<br>`HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager`<br>可脚本化 · `-Phase tune` | WPBT 让 OEM 固件在每次开机时注入并执行一个二进制——不经过安装流程、不是驱动、也没有正常的签名与更新链路，是本项目唯一要关掉的「固件级、不可见」执行路径。 | `$tweaks` → **wpbt blocked**，期望 `1`。 |
| **PreventDeviceMetadataFromNetwork = 1**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata`<br>可脚本化 · `-Phase tune` | 插上显示器 / 打印机 / 音频设备时，系统会按设备元数据去商店找「配套应用」并推送安装；关掉这条网络取元数据的路径即可，已装的设备照常工作。 | `$tweaks` → **device metadata off**，期望 `1`。 |
| **快照目录存在 `tune-undo-<yyyyMMdd-HHmmss>.ps1`，条目数 = 实际应用的写入数**<br>`<快照目录>\tune-undo-*.ps1`<br>可脚本化 · `-Phase tune` | 还原点是粗粒度：一个坏 tweak 会连带回滚掉好的。撤销脚本逐项恢复**写入前的实际值**，原本不存在的值删掉——不是写回一个猜的「微软默认」。 | 看文件存在与条目数；`-WhatIf` 下不生成（没有应用任何写入）。`verify-env.ps1` 不检查这个文件。 |

## 磁盘与界面

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **StoragePolicy 08 = 1**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy`<br>可脚本化 · `-Phase tune` | 存储感知默认只清临时文件，清空回收站是 opt-in。 | `$tweaks` → **recycle bin cleanup**，期望 `1`。 |
| **StoragePolicy 32 = 30**<br>同上键<br>可脚本化 · `-Phase tune` | 回收站保留 30 天。 | `$tweaks` → **recycle retention**，期望 `30`。 |
| **经典右键菜单：`InprocServer32` 默认值 = 空字符串**<br>`HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32`<br>可脚本化 · `-Phase tune` | Win11 的折叠右键菜单由这个 shell extension 提供，把它的 `InprocServer32` 默认值置空即禁用该扩展。默认值不能进批量 `.reg`（批量读回按值名查，读不到默认值），所以单独写。出厂 Win11 上这个键不存在，撤销要删整个 CLSID 键而不是写回空串。 | `$tweaks` → **classic context menu**：`(Get-ItemProperty 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32').'(default)'` 必须等于空字符串；键不存在 = 折叠菜单仍在用 = FAIL；生效需重启 Explorer。 |

存储感知的「自动清理下载文件夹」刻意不启用：会删掉用户的安装包，省的空间微不足道。

## 后台与锁屏

三条写入，管的是后台驻留与锁屏信息暴露，不是帧率。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **GlobalUserDisabled = 1**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications`<br>可脚本化 · `-Phase tune` | 商店应用不能在后台执行；前台使用不受影响，只是不再常驻。与「关推广」是两件事：那个关的是内容推送，这个关的是进程驻留。 | `$tweaks` → **background apps off**，期望 `1`。 |
| **LockScreenToastEnabled = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications`<br>可脚本化 · `-Phase tune` | 锁屏上不显示通知内容。锁屏是「物理在场即可见」的状态，通知正文不该无条件展示。 | `$tweaks` → **lock screen toasts off**，期望 `0`。 |
| **NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings`<br>可脚本化 · `-Phase tune` | 同一个开关的用户级设置作用域；两处各自独立被读取，所以两处都写，验收也分别计分。 | `$tweaks` → **toasts above lock off**，期望 `0`。 |

## 隐私面

四条策略写入 + 三条用户级写入。收益是「不再用于画像/个性化」，不是性能。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **AdvertisingInfo\Enabled = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo`<br>可脚本化 · `-Phase tune` | 广告 ID 是跨应用的关联键：关掉后应用无法拿到同一个 ID 做画像。 | `$tweaks` → **advertising id off**，期望 `0`。 |
| **TailoredExperiencesWithDiagnosticDataEnabled = 0**<br>`HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy`<br>可脚本化 · `-Phase tune` | 「用诊断数据做个性化提示」的同意项。与遥测等级是两件事：等级决定传多少，这条决定拿它做什么。 | `$tweaks` → **tailored tips off**，期望 `0`。 |
| **PublishUserActivities = 0 / EnableActivityFeed = 0**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Windows\System`<br>可脚本化 · `-Phase tune` | 同一组策略下的两个开关：`PublishUserActivities` 管活动历史上传，`EnableActivityFeed` 管活动源本身；验收对两者分别计分，缺一条就有一条 FAIL。 | `$tweaks` → **activity upload off** / **activity feed off**，均期望 `0`。 |
| **AllowInputPersonalization = 0**<br>`HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization`<br>可脚本化 · `-Phase tune` | 输入法/手写的用户词典上传。关掉不影响本地词库与输入。 | `$tweaks` → **input personalization off**，期望 `0`。 |
| **HasAccepted = 0**<br>`HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy`<br>可脚本化 · `-Phase tune` | 在线语音识别同意项。关掉后语音输入退回本地引擎，仍可用。 | `$tweaks` → **cloud speech off**，期望 `0`。 |
| **StartupBoostEnabled = 0**<br>`HKLM:\SOFTWARE\Policies\Microsoft\Edge`<br>可脚本化 · `-Phase tune` | Edge 的启动预加载：常驻一批预读进程换取首次启动速度。关掉后首次启动变慢，但不占常驻内存。 | `$tweaks` → **edge startup boost off**，期望 `0`。 |

## 游戏模式与界面

三条写入 + 一条手工项。

| 正确值 | 判据（为什么是这个值） | 怎么验 |
|---|---|---|
| **AutoGameModeEnabled = 1**<br>`HKCU\Software\Microsoft\GameBar`<br>可脚本化 · `-Phase tune` | 游戏模式让 Windows 压掉后台工作并优先调度游戏线程。出厂通常已是 1，写它是**钉住**，防止被其它"优化"改回 0。 | `$tweaks` → **game mode on**，期望 `1`。 |
| **ShowCloudFilesInQuickAccess = 0**<br>`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer`<br>可脚本化 · `-Phase tune` | 快速访问会去查 Office.com 云端文件：既是视觉噪声，也是每次打开资源管理器的一次云调用。 | `$tweaks` → **cloud files in quick access off**，期望 `0`。 |
| **LegacyDefaultPrinterMode = 1**<br>`HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows`<br>可脚本化 · `-Phase tune` | Win10 起默认打印机会「自动切到最近用过的打印机」，在多打印机环境里等于替你改设置。此值锁回手动管理。 | `$tweaks` → **default printer pinned**，期望 `1`。 |

> [!WARNING]
> **Widgets 订阅源（Dsh）只能手工关。** `HKCU\Software\Policies\Microsoft\Dsh` 与 `HKLM\SOFTWARE\Policies\Microsoft\Dsh`
> 的 `AllowNewsAndInterests` 在本机是 **ACL 锁定**的：Owner 是 `BUILTIN\Administrators`，但交互用户只有 `ReadKey`，
> `reg add`（含提权）返回 `Access is denied`。这类写不进去的键**不放进 tune** —— 否则会变成一条永远失败的假 tweak。
> 要关订阅源：设置 → 个性化 → 任务栏 → 关闭小组件；或用组策略编辑器。
## 手工项

以下 9 项不进 tune 的默认写入：要么没有可靠的自动化路径，要么正确值取决于机器形态与个人取舍。

- **杀毒软件信任区 / 排除项**（需手工，无脚本）：第三方杀软接管时 Defender 停用是正常让位，不是故障；排除项只能进厂商界面或厂商 CLI，各产品不同，脚本代劳会写错位置、还会静默失败。本项目不卸载、也不配置任何第三方安全软件。
  本机实测待排除目录：`C:\Program Files (x86)\Steam\steamapps`（74.3 GB）、`C:\WeGameApps`（52.7 GB）。火绒的信任区配置存放在 `C:\ProgramData\Huorong\Sysdiag`（二进制、受保护），**没有公开 CLI**，只能进界面添加：火绒 → 安全设置 → 信任区 → 添加目录。只排除只读的游戏/代码内容，不要排除 `Downloads`、`AppData` 或整盘。
- **预装 App 清理**（需手工，无脚本）：tune 只关推荐与静默安装（`DisableWindowsConsumerFeatures` + `ContentDeliveryManager` 各值），**从不卸载任何 App**；删哪些是使用习惯，删掉不可逆。
- **默认程序关联**（需手工，link 阶段只做注册与报告）：Windows 保护 `UserChoice`，每个文件类型要一次手工点击：右键 > 打开方式 > 选择其他应用 > 勾「始终」。
- **显卡驱动 + CUDA/torch 栈**（需手工，drivers 阶段只做分诊）：装哪个驱动、哪个 torch build 取决于显卡与驱动版本，vendor 特定；drivers 阶段只列失败设备与 Windows Update 提供的驱动。
- **有线网卡省电**（需手工，但验收会查）：正确状态是每块 Ethernet 适配器的 `PnPCapabilities = 24`；值为 0 时 Windows 可以关掉网卡省电，表现为游戏里随机掉线。tune 不写这个值（厂商工具 / 设备管理器 / 手工注册表），`verify-env.ps1` 的 **nic power saving** 却会逐块比对——典型「验收查、tune 不写」。
- **休眠取舍**（需手工决策，`-DisableSleepOnAC` 可代劳）：台式机 / 迷你机上 S0 modern standby 实测唤不醒——五次睡眠都是 187 → 42 → 107（2–4 秒后「醒」）→ 数小时待机 → 507，其中一次再没醒，只能强制断电，记为 Id=41 + 6008。AC 下关睡眠、保留显示器超时，能移除这类故障；笔记本相反，所以默认关闭。
- **电源方案**（需手工决策，`-HighPerformancePowerPlan` 可代劳）：高性能方案的代价是续航，笔记本不该默认开。
- **鼠标加速**（需手工决策，`-DisableMouseAcceleration` 可代劳）：会写 `HKCU:\Control Panel\Mouse` 的 `MouseSpeed` / `MouseThreshold1` / `MouseThreshold2 = 0`；这是偏好，不是通用收益。
- **页面文件**（需手工，默认即正确）：正确状态是系统托管（`AutomaticManagedPagefile = True`）；手工设一个很小的固定值会伤游戏与 AI 负载。tune 不写，`verify-env.ps1` 的 **pagefile** 只读检查。

## 维护约束

- **改一处就要改两处**：`setup.ps1` 的 `$changes` 与 `verify-env.ps1` 的 `$tweaks` 是同一份契约的两半。加一个写入就加一条 `Want`，改一个值就同时改两边的字面量；只改一边的结果是「写了没人验」或「验的从没写过」。
- **`Want` 不许写死**：`AllowTelemetry` 由 `EditionID` 决定（`Enterprise` / `Education` / `Server` 之一 → 0，其余 → 1），两边必须用同一个判定表达式，否则专业版上会出现永久 FAIL。
- **结果型检查不许退化成开关检查**：`EnablePeriodicBackup=1` 不等于有备份（26xxx 上任务空壳、SIT 已消失、RegBack 长期 0 字节），所以查 RegBack 字节数；MMCSS 同理查 `sc query` 的 RUNNING，而不是注册表值。
- **覆盖差额要显式**：tweaks 组共 49 条检查（41 条在 `$tweaks` 表内、1 条经典右键菜单、4 条结果检查）；43 个值里 42 个有逐值检查，`EnablePeriodicBackup` 改查结果——**没有「写了但没人查」的值**。
- **批量 `.reg` 的两个已知行为**：可写性未知的键不要放在批次中间（`reg import` 会部分写入、exit 1、跳过余下段）；`ContentDeliveryManager` 上实测被静默跳过，已有逐值直写兜底。
- **改完跑体检**：`scripts/check-script-hygiene.ps1`（该目录 ASCII-only，5.1 也会加载）与 `scripts/test-tune-core.ps1`（DWORD 渲染、build 门控等纯函数）。

---

<p align="right"><sub><a href="./README.md">← 目录</a> · <a href="./02-decisions.md">← 02 决策</a> · <a href="./04-dev-and-apps.md">04 环境与软件 →</a> · <a href="../README.md">笔记本</a></sub></p>
