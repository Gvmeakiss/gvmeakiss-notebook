# Windows 优化决策：哪些值得做，哪些不要做

证据由证据审查那一份汇总（谁的源码、谁测出的数字），这一份只回答两个问题：**这条改动做不做**、**这台机器上做了没有**。
判定口径固定三步：机制能不能讲通 → 有没有测量 → 在本类机器（45 W APU + 核显）上代价是什么。品牌名、魔数与「大神说」都不进这三步。

> 标「无测量」的地方就是没有测量，不要当成有效。凡是只改注册表值、没有行为回读的，一律按未验证处理。

---

<details>
<summary><b>本页目录</b>（5 节）</summary>

- [1. 值得做](#1-值得做)
- [2. 不要做](#2-不要做)
- [3. 本类机器的默认决策](#3-本类机器的默认决策)
- [来源说明](#来源说明)
- [4. 从 Winhance / Bloatynosy 源码里读到、明确不要照抄的](#4-从-winhance--bloatynosy-源码里读到明确不要照抄的)

</details>

## 1. 值得做

| 项 | 机制 | 预期收益 | 风险 | 本机是否已应用 |
|---|---|---|---|---|
| **游戏内帧率上限**，压在实测可持续帧率之前 | 削掉每帧的功耗尖峰：功耗平→boost 稳→帧时间稳。PC-Tuning 的限帧一节就是这个结论——省下的是**每帧几毫秒**，而计时器精度只值几微秒 | 1% low 明显变稳，风扇更安静 | 限得过低直接牺牲响应性，必须按游戏单设 | ✅ 按游戏设，见 [05-games/](../games/README.md)（CS2 现成结论是 `fps_max 120`：略高于刷新率，但压在核显满载点之前） |
| **电源方案保持 Balanced**，不锁最高性能 | 「高性能」方案原文是「把处理器锁在最高性能状态（含 turbo）、所有核 unpark……热量输出可能很显著」。45 W 的 APU 与 780M 共用同一份功耗/热预算，锁死等于把余量从核显手里拿走 | 给 iGPU 留功耗与散热余量；避免 STAPM 降频 | 突发负载的上升沿略慢（但 `RESP*` 机制本来就在补：DPC 计数超阈值时抬频率地板，默认 enable 10 / disable 5、地板 100%） | ✅ 保持 Balanced，未用 Ultimate Performance；`PROCTHROTTLEMIN` 未单独回读 |
| **MMCSS `SystemResponsiveness=10`**（`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile`） | 该值 = 留给低优先级任务的 CPU 百分比。10 既是 10 的整数倍、又不小于 10，所以不被取整也不被 clamp——**真的**把预留从默认 20 降到 10 | 多媒体线程拿到更多 CPU 份额 | 后台任务（含桌面响应）份额变少；没有「提升帧数」的测量 | ✅ 已应用（`verify-env.ps1` 期望值即 10） |
| **`NetworkThrottlingIndex=0xffffffff`**（同键） | 关掉 MMCSS 对网络收发的节流配额 | 多媒体负载下不再被节流 | 抢占式网络负载时其他流量更难受 | ✅ 已应用 |
| **只读测量基线**：`ClockRes`、`MeasureSleep`、`xperf` DPC/ISR、PresentMon、HWiNFO | 没有测量就无法区分「注册表写对了」与「行为真的变了」；xperf 的 DPC/ISR 报告是判断中断落在哪个核的唯一依据 | 后面每条改动可 A/B，避免把 no-op 当收益 | 花时间；trace 期间帧率不能用于评价 | ✅ 常备（PresentMon + HWiNFO） |
| **还原点 + 绕过 dedupe**，`EnablePeriodicBackup=1` | 系统保护快照是唯一**保证可用**的粗粒度回滚；绕开 dedupe 限制，小盘也存得下。`EnablePeriodicBackup=1` 写的是「允许周期性创建」，填充发生在后续某个启动/空闲点（实测启用后立即查为 0 字节，两天两次重启后为 110 MB），因此它**不能**当作即时可用的安全网 | 改坏了能整体退回 | 占空间；BSOD 级改动不一定还能进得去系统还原 | ✅ 已建还原点（含 dedupe 绕过）+ `EnablePeriodicBackup=1`；但**本机实测该开关在 Win11 26xxx 上是 vestigial**：值读回 1，RegBack 仍 0 字节，所以安全网是还原点，不是注册表备份 |
| **遥测收敛**：策略 + 计划任务 + DiagTrack 出站防火墙 | 关的是上报通道与触发任务，不是关服务本身，因此不触碰调度层 | 少掉后台网络与磁盘写入 | 裁得过头会牵连 Store/更新——PC-Tuning 记录过「禁 Windows Update 会坏掉 Store」，所以这里只封 DiagTrack 出站 | ✅ 已应用 |
| **AC 下禁用睡眠**（tune 只把 AC 的 standby/hibernate 超时置 0；本机另外手工执行了 `powercfg /hibernate off`，那是手工项不是 tune 行为） | 唤醒后外设与网络栈重连是已知的故障源（本仓库 NAS 专项就定位在这）；休眠文件占用的磁盘等于整份内存 | 不再有唤醒后掉线；手工关休眠后再省下 `hiberfil.sys` | 断电即丢会话；带电池的机器不适用——本类是 mini-PC | ✅ 已应用 |
| **关 GameDVR / 后台录制** | 策略 `HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR` → `AllowGameDVR=0`，加用户层 `HKCU\System\GameConfigStore\GameDVR_Enabled=0`，去掉捕获管线（`AppCaptureEnabled=0` 属同类设置，但 **tune 不写它**，仅作为可选手工项） | 少一条常驻的后台捕获开销（无公开帧时间数字） | 失去 Win+Alt+R 录屏 | ✅ 已应用 |
| **`DODownloadMode=1`**（`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config`） | 传递优化只走**局域网**，不再向互联网上传、也不替他人做种（`1` = LAN-only；`0` 才是 HTTP-only，两者不要混淆） | 不占上行，不在后台替别人做种 | 多机同网时失去局域网加速 | ✅ 已应用 |
| **`PreventDeviceEncryption=1`**（`HKLM\SYSTEM\CurrentControlSet\Control\BitLocker`） | 阻止满足条件的机器自动开 BitLocker 设备加密；自动加密把恢复密钥绑到账户，重装或换主板后锁盘 | 避免「半夜自动加密」 | 真要加密得手动开 | ✅ 已应用 |
| **StorageSense 管回收站**（`StoragePolicy` → `08`=1、`32`=30） | 定时清空回收站并限定保留天数 | 小盘空间 | 误删文件过了期限找不回 | ✅ 已应用（30 天） |
| **经典右键菜单**（`CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32` 默认值置空） | 跳过 Win11 折叠菜单，直接展开完整项 | 操作步数减少 | 累积更新后可能被覆盖，需复查 | ✅ 已应用（**不是延迟改动**） |
| **HAGS 保持默认，不改** | WDDM 2.7+ 把 GPU 调度（quanta 管理、上下文切换）下放到 GPU 侧调度处理器，省掉那个高优先级 CPU 调度线程。各家统一写 `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` → `HwSchMode`=2 开 / 1 关；但值名不在微软公开注册表参考里，1/2 映射属于「广泛一致、未官方文档化」，以 设置 → 显示 → 图形 为准 | 现代特性的前提（如 DLSS Frame Generation）——这才是留着它的真实理由 | 任何仓库都没有「降低延迟」的测量；老驱动上偶有兼容问题，出问题再关 | ⚠️ 保持默认（本机未改） |
| **中断亲和力：只在测到噪声后应用** | `...\Interrupt Management\Affinity Policy` → `DevicePolicy`=4（`IrqPolicySpecifiedProcessors`）+ `AssignmentSetOverride`=小端 KAFFINITY 掩码，微软文档写明它们对应 `u.Interrupt.AffinityPolicy`/`TargetedProcessors`。顺序是：先 xperf 看谁在服务该模块，再用 AutoGpuAffinity 逐核测 GPU/DXGK 的 DPC-ISR 时间，最后才写掩码 | 只在真的错位时有收益；没有仓库给出群体数字，这是「测自己那台」而非通用 tweak | 核心停泊可能把掩码**之外**的核 unpark，两者互相打架；改错要重启驱动 | ❌ 刻意未做（本机无测量依据） |
| **计时器分辨率：只在测到坏了才开，优先 per-process** | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel` → `GlobalTimerResolutionRequests`=1，恢复 2004 之前的全局语义：一个进程调 `NtSetTimerResolution`/`timeBeginPeriod` 影响全系统 | 只对基于 sleep 的限帧器与音频有意义 | 更频繁唤醒空闲核→功耗/发热/风扇；Win11 在窗口最小化或被遮挡时撤销请求，除非用 `SetProcessInformation(PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION)` | ❌ 刻意未做（本机未测到问题，即不强开） |
| **显示/驱动卫生**：原生分辨率、不做 GPU 缩放、干净装驱动、停用不用的 USB/音频设备 | 去掉一次插入的缩放与多余设备带来的中断/轮询 | 少一类抖动来源 | 无（换驱动本身有风险） | ✅ 部分（原生 4K、无缩放） |
| **WPBT 阻断**（`DisableWpbtExecution=1`） | WPBT 允许 OEM 固件在每次开机注入执行一个二进制，不经安装流程、不需要驱动 | 关掉一条固件级、不可见的启动执行路径 | 无（本机无功能依赖它） | ✅ 已应用 |
| **设备元数据不联网**（`PreventDeviceMetadataFromNetwork=1`） | 插设备时系统会按元数据去商店找配套应用并推送安装 | 少一类「插上就装东西」 | 新设备不会自动推荐应用 | ✅ 已应用 |
| **后台应用禁用**（`GlobalUserDisabled=1`） | 商店应用不在后台执行；与「关推广」是两件事（那是内容推送） | 少掉一批后台进程与磁盘唤醒 | 依赖后台刷新的应用（如邮件）需前台打开才同步 | ✅ 已应用 |
| **备份保留两代**（`BackupCount=2`） | 只与 `EnablePeriodicBackup` 配合有意义：默认只留一代，覆盖后无法比对上一份 | hive 损坏时多一个可回退版本 | 占用少量磁盘 | ✅ 已应用 |
| **锁屏不显示通知内容**（`LockScreenToastEnabled=0` + `NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK=0`） | 锁屏是「物理在场即可见」的状态，通知正文不该无条件展示 | 信息不外泄 | 锁屏只剩时间日期 | ✅ 已应用 |
| **广告 ID 与画像数据**（`AdvertisingInfo\Enabled=0`、`TailoredExperiencesWithDiagnosticDataEnabled=0`） | 广告 ID 是跨应用关联键；「用诊断数据做个性化」决定的是拿数据做什么。两者与遥测**等级**是三件不同的事 | 不再被画像 | 无 | ✅ 已应用 |
| **活动与输入遥测**（`PublishUserActivities=0`、`EnableActivityFeed=0`、`AllowInputPersonalization=0`、`Speech_OneCore\…\HasAccepted=0`） | 时间线上传、跨设备剪贴板、云端语音、输入法词库上传是四条独立通道，各自有策略键 | 少四类出站数据 | 云端听写与时间线不可用；本地语音与输入不受影响 | ✅ 已应用 |
| **Edge 启动预加载**（`Edge\StartupBoostEnabled=0`） | Edge 会常驻一批预读进程换首次启动速度 | 不占常驻内存 | 首次启动变慢 | ✅ 已应用 |
**关于计时器的一条附注。** PC-Tuning 在 Win11 22H2 上用 `NtQueryTimerResolution` + QPC 量 `Sleep(1)`，加键后从 **~15.5 ms 降到 ~1.5 ms**，并用 IDA/WinDbg 确认内核符号 `KiGlobalTimerResolutionRequests` 在 Win10 2004–22H2 **根本不存在**（在那里写了也是 no-op）。
同一批测量还有个反直觉结果：请求 1.000 ms 实测 delta ≈0.999 ms，请求 0.500 ms 实测 ≈0.496 ms，而请求 **0.507 ms** 反而只有 ≈0.012 ms——请求周期是与硬件时钟量化后的结果，「最高」分辨率不等于最准；30+ 人复现，少数机器要用 0.6 ms，Win7 表现不同。
所以别把「设成最大值」当优化。而且这套测量量的是 **sleep 精度**，不是输入到出画的延迟，只在基于 sleep 的限帧器/音频上有关。

---

## 2. 不要做

| 项 | 为什么（机制层面） | 常见错误说法 |
|---|---|---|
| **HPET / `useplatformclock` / `disabledynamictick`**，乃至改 DSDT（GRUB 法或测试签名驱动）删掉 HPET 设备 | Win8 起 Windows 用 invariant TSC 作 QPC 基准，只有 TSC 不合格才回落到 HPET/ACPI-PM。微软文档写明平台计时器「访问延迟高于 TSC，且在多处理器间共享」，每次调用 QPC 约 **0.8–1.0 微秒**（TSC 是数十到数百周期）且要走内核转换——强制平台时钟等于把计时搬到**更慢**的设备。`disabledynamictick` 关的是动态 tick/合并，是调试开关，代价是功耗与发热 | 「HPET 精度更高，关掉能降延迟」「BIOS 里必须先关 HPET」。Hyyote 自己都写 DSDT 补丁会和不少反作弊冲突 |
| **核心停泊 `.reg`**（`ValueMax=0`、`ValueMin=0`；hellzerg 的 `UnlockAllCores()` 写的是同一对值） | 它写的是 `...\Control\Power\PowerSettings\54533251-…\0cc5b647-c1df-4637-891a-dec35c318583`（CPMINCORES）的**元数据树**——定义取值范围与可见性——而不是活动方案值（后者在 `...\PowerSchemes\…` 下，`powercfg /q` 读的那份）。两个问题：a) 运行中的方案未必变；b) 就算 clamp 生效，把 CPMINCORES 的最小值 clamp 到 **0**，含义是「至少 0% 的核 unpark」，与「关掉停泊」正相反。正确写法是 `powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100` + `powercfg /setactive` | 「关核心停泊能减少调度延迟」。**口径**：ValueMin/Max 语义来自 PowerSettings schema，两个文件都没执行 → 记为**很可能是坏的**，不是已证坏 |
| **批量禁服务 / Nuke 式裁剪**（18 个阶段） | 删服务、删 ETW autologger、删事件日志通道、删 WER，还把 `wer.dll` 换成桩——没有一条是延迟机制；而删掉 ETW 与事件日志，正好毁掉验证延迟要用的工具（xperf、WPR、PresentMon 的 trace）。微软自己的软实时指南只允许禁 **SysMain、DPS、Audiosrv、Windows Update** 四个，前提是「为特定用途定制的应用与设备」，并写明「会把设备暴露在漏洞下」、误用 RT-core CSP「会导致系统故障并要求重装」；而那个 Nuke 脚本的作者自己在 README 里标的是「No backups… irreversible」 | 「服务越少越快」。Hyyote 的 README 自己承认 Win11 只能压到 ~31 个服务（Win10 是 ~22 个） |
| **`Win32PrioritySeparation` 魔数 36 / 38** | 实测的内核读取表（djdallmann，PC-Tuning 用 WinDbg 复核）：默认 2 → Shorter/Variable，前台 18 / 后台 6（3:1）；**36 → 6/6，等于把前台 boost 去掉**；38 → 18/6，效果等同默认；40 → Shorter/Fixed，18/18。内核只读 6 bit，所以 >0x3F 的值只是别名 | 「38 = 短、固定、3:1」，与实测表直接矛盾 |
| **活体内核补丁**（`ed nt!KiQuantumEnd 0`、`PspComputeQuantum`、`ExpTimerResolutionCount`、`eb nt!KiIdleLoop 90`、清 `KeFeatureBits`/`HvlEnlightenments`） | 用 LiveKD/WinDbg 改**正在运行**的内核：不持久、不受支持、无回滚路径，且直接关掉系统依赖的调度与计时记账。`PspComputeQuantum=0` 与 `KiIdleLoop` 补丁属于「当场挂」的候选 | 「改内核变量砍掉调度开销」 |
| **把 CPU 钉死在最高状态**：`PROCTHROTTLEMIN 100`、Ultimate Performance、禁用 C-state 0 | 强行 C0 抬高温度与功耗、干扰 boost 算法（PBO/Turbo），SMT 开启时单线程更差。在 CPU 与 780M 共享一份功耗/热预算的 45 W 机器上，这是「帮倒忙」最清楚的一例（PC-Tuning 一边写明机制，一边劝退大多数用户） | 「禁 C-state 消除唤醒延迟」「锁 100% 更稳」 |
| **MSI 模式**（尤其核显） | MSI 把线中断换成内存写，机制真实，但会 BSOD（例如 Win7 自带的 SATA 驱动），厂商有时故意不发 MSI（NVIDIA 按架构而不同）；核显中断在 die 内、没有 PCIe 那一跳，预期收益比独显更小；读过的来源里没有任何帧时间/延迟改善的测量 | 「MSI 模式必开，开了延迟更低」 |
| **`bcdedit` 杂项**：`numproc %NUMBER_OF_PROCESSORS%`、`nx alwaysoff`、`hypervisorlaunchtype off`、`disableelamdrivers yes`、`tpmbootentropy forcedisable`、`isolatedcontext no`、`vsmlaunchtype off`、`useplatformtick yes` | `numproc` 设成当前核数就是 no-op；其余拿安全与可靠性（以及 HVCI 的可用性）换不到任何测得收益；`useplatformtick`+`disabledynamictick` 还会抬高待机功耗，在 mini-PC 上完全反向 | 「关掉 hypervisor 能提速」「numproc 限核更稳」 |
| **`SystemResponsiveness=0` 或 `=1`** | 微软文档：不可被 10 整除的值向下取整，**小于 10 与大于 100 一律 clamp 回 20**，100 直接关闭 MMCSS。所以 0 与 1 都被打回默认 20，是**文档化的 no-op**。hellzerg 的「撤销」写 **14**，取整到 10——所谓还原之后，机器仍停在非默认值 | 「设 0 让游戏吃满 CPU」 |
| **把 Game Mode 当 tweak 开或关** | 结论是**不确定**：PC-Tuning 唯一的说法是它「可能干扰进程与线程的优先级 boost」（可用 *Windows Internals* 的 PerfMon 线程优先级实验复现），并会压制 Windows Update 与通知，建议 A/B 而不是下判决。hellzerg 把 `AutoGameModeEnabled=1` 与 HAGS 打包成 `EnableGamingMode`，把两件不相关的事混成一个开关 | 「关掉游戏模式帧数更高」／「开游戏模式一定更好」 |
| **为游戏关掉 VBS/HVCI（+ Virtual Machine Platform）** | 微软自己的游戏性能页承认「在某些场景与某些游戏设备配置下，内存完整性与 VMP 可能带来性能影响」，并把关掉列为受支持的选择（附安全警告）——方向厂商确认，但读过的来源里**没有按标题的数字**，量级未知。反作弊有例外：Vanguard/FACEIT 可能**要求** HVCI。**本机：LoL 走 Vanguard，故保留 ON**；只有换掉这类游戏后才值得 `msinfo32` 确认 + CPU 密集型基准与 1% low 各 A/B 一次 | 「关掉 VBS 白送 10% 帧数」——方向对，数字没有出处 |

**唯一站得住的「禁用」**：WSearch/SysMain（后台 I/O 与 CPU）与游戏目录的 Defender 实时扫描。这两项是 I/O/CPU 噪声的减法，不是调度延迟的修复，读过的仓库里没有一条量化；而 Win11 上关 `WpnService`、`StateRepository`、AppX/ClipSVC 是已知的坏法。

**两条旁证。** 3.9k 行的 Disassembler0 `Win10.psm1`（隐私/服务/计划任务，成对的 Enable/Disable 函数）里**没有**任何 HPET、MMCSS、计时器、核心停泊改动——这个公认「正经」的基线是故意不写这些的。
而这片领域里最看重测量的 PC-Tuning，通篇也没有 `useplatformclock`/`disabledynamictick`/HPET 一节。没人写，不是没想到，是不该写。

---

## 3. 本类机器的默认决策

**平台**：Ryzen 7 255 = Hawk Point / Zen 4，8C/16T，16 MB L3，Radeon 780M（12 CU，≤2.6 GHz），45 W TDP（35–54 W 可配），DDR5-5600/LPDDR5x-7500，无启用 NPU。
**本机**：核显输出、**21.8 GB 与 CPU 共享的 LPDDR5X**、**4K 60 Hz** 面板。这两条决定了下面一半的取舍。

**执行顺序**：先有还原点 → 再落地零风险的卫生与安全网项 → 再定帧率与电源 → 最后才是需要测量的项。反过来做（先改注册表、后找测量）正是那台「已优化机」的来路。

### 3.1 帧率：先封顶，再谈别的

- **决策**：上限设在实测可持续帧率之前，不是照抄面板 60。要更高帧就先降分辨率到 1080p/1440p 并用原生分辨率输出，**不做 GPU 缩放**（驱动缩放是插入的一次额外处理，与「限帧换稳定」方向相反）。
- **判据**：PresentMon 抓帧时间曲线与 1% low；GPU 占用不长期 99–100%、温度随之下降，才算限帧生效。

### 3.2 共享内存：是带宽问题，不是容量问题

- **决策**：BIOS 的 UMA frame buffer 保持默认，不追 4 GB+ 的「核显显存」。LPDDR5X 带宽由 CPU 与 iGPU 分食，调大帧缓冲不会多出带宽，只会少给系统内存。降画质按「分辨率 → 阴影 → 后处理」的顺序压。
- **判据**：同一场景降一档分辨率就明显回帧 = 带宽/填充率受限，此时动注册表没有任何帮助。

### 3.3 电源：Balanced + 小的 AC 地板

- **决策**：Balanced，`PROCTHROTTLEMIN` 保持 5（不是 100），`PERFBOOSTMODE` 留默认（GUID `be337238-0d82-4146-a960-4f3749d470c7`，0 Disabled … 2 Aggressive），`DISTRIBUTEUTIL` 按微软建议对突发/快速迁移负载关闭。不用 Ultimate Performance。
- **判据**：`powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN` 读回 5；HWiNFO 的**有效频率**与温度墙/STAPM 标志确认游戏时不是热限——这是这台 45 W 机器上最值得做的一次减法。

### 3.4 计时器：默认不动

- **决策**：不开 `GlobalTimerResolutionRequests`。它只在 Win11/Server 2022+ 有意义，代价是更频繁唤醒空闲核；4K 60 Hz 的场景里换不来可感知收益。
- **判据**：`ClockRes` 看 current/min/max，`MeasureSleep` 打实际 `Sleep(1)` delta。限帧器不抖就不改；测量要在负载下做，空载的数字不算；要改也优先 per-process，并记住窗口最小化会撤销请求。

### 3.5 中断与 MSI：只测不动

- **决策**：核显中断在 die 内，没有 PCIe 一跳，收益比独显小；MSI 模式不碰（BSOD 风险换不到测得的好处）。
- **判据**：`xperf -on PROC_THREAD+LOADER+DPC+INTERRUPT`（或 `xtw`）抓一段，看每个模块的 ISR/DPC 落在哪个核、是否同核；AutoGpuAffinity 的逐核数据若显示明显错位，才值得写 `DevicePolicy=4` + 掩码。

### 3.6 安全与回滚：不让步

- **决策**：VBS/HVCI 保留 ON（Vanguard 要求）；遥测只封 DiagTrack 出站，不碰 Windows Update；动任何东西之前先有还原点，改完**重启**再验证，一次只改一项。
- **判据**：`msinfo32` 的「基于虚拟化的安全性」与「HVCI」两项为开启；还原点列表里有本次改动之前的点。

### 3.7 本机状态回读

**已应用（11 项）**：GameDVR 关 · MMCSS `SystemResponsiveness=10` + `NetworkThrottlingIndex=0xffffffff` · 遥测策略 + 计划任务 + DiagTrack 防火墙 · 还原点（dedupe 绕过）· AC 禁睡眠 · 休眠关 · 经典右键 · `DODownloadMode=1` · `PreventDeviceEncryption=1` · `EnablePeriodicBackup=1` · StorageSense 清回收站。

**刻意未做的 8 项**（理由全部在 §2，不重复）：
- HPET / `useplatformclock` / `disabledynamictick` —— 把计时搬到更慢的平台计时器上。
- 核心停泊 `.reg` —— 写的是元数据树，且数值语义与意图相反。
- 服务裁剪 —— 没有延迟机制，还会毁掉验证工具。
- MSI 模式 —— 核显收益小，风险是 BSOD。
- 中断亲和力 —— 没有本机测量依据就不写掩码。
- 强制计时器分辨率 —— 未测到问题，强开只是加热。
- `Win32PrioritySeparation` —— 36 去掉前台 boost，38 等于默认。
- 活体内核补丁 —— 不持久、无回滚，且可能当场挂。

**保持默认（2 项）**：HAGS 不动（本机未改；留它是为了现代特性前提，不是为了延迟）；VBS/HVCI 刻意 ON（LoL 走 Vanguard）。

**部分应用（1 项）**：显示/驱动卫生 —— 原生 4K 与「不做 GPU 缩放」已确认；干净驱动与停用多余 USB/音频设备是持续动作，不是一次性开关。

### 3.8 验收协议

改动前后各跑同一段回放；PresentMon 取 1% low 与帧时间曲线，HWiNFO 记有效频率/温度/功耗，可疑时补一次 xperf 的 DPC/ISR 报告。**差异落在噪声里就回滚**，不做「感觉快了」的保留。
记录格式固定为：日期 / 项 / 改前值 / 改后值 / 判据结果 / 是否保留 —— 没有这一行的改动等于没做。

### 3.9 什么情况下要回头改结论

- 换掉 Vanguard 类反作弊 → 重新评估 HVCI（唯一一处「保留 ON」的前提变了）。
- 换独显（真 PCIe 链路）→ 中断与 MSI 的收益假设要重算。
- 换面板或分辨率（4K → 1440p）→ 帧率上限、UMA 取值与画质档位一起重算。
- 累积更新删掉某项基线值 → 按 [03 系统调优清单](./03-system-tweaks.md) 复查并修文档。
- 新版本的 `GlobalTimerResolutionRequests` 行为变化 → 重跑 `ClockRes` + `MeasureSleep` 再决定。

---

## 来源说明

只读拉取源码与文档、未执行任何脚本：Hyyote [README](https://github.com/Hyyote/In-depth-Windows-tweaking/blob/main/README.md)、[Pro1.bat](https://github.com/Hyyote/files-/blob/main/tweaks/Pro1.bat)、[settings for disabled HPET.bat](https://github.com/Hyyote/files-/blob/main/tweaks/settings%20for%20disabled%20HPET.bat)、[Disable core parking.reg](https://github.com/Hyyote/files-/blob/main/tweaks/Disable%20core%20parking.reg)、[Nuke/README.md](https://github.com/Hyyote/files-/blob/main/tweaks/Nuke/README.md)、[HPET patch/README.md](https://github.com/Hyyote/files-/blob/main/tweaks/HPET%20patch/README.md)、[Setup-GRUB-HPET.ps1](https://github.com/Hyyote/files-/blob/main/tweaks/HPET%20patch/GRUB%20method/Setup-GRUB-HPET.ps1)、[kernel settings](https://github.com/Hyyote/files-/blob/main/kernel/Usage%20and%20personal%20settings.txt)；AntonSiMal [UltimateWindowsOptimizer.bat](https://github.com/AntonSiMal/Windows-Optimizer/blob/main/UltimateWindowsOptimizer.bat)；luke-beep [DATABASE.md](https://github.com/luke-beep/all-about-windows/blob/main/docs/DATABASE.md)；Disassembler0 [Win10.psm1](https://github.com/Disassembler0/Win10-Initial-Setup-Script/blob/master/Win10.psm1)；hellzerg [OptimizeHelper.cs](https://github.com/hellzerg/optimizer/blob/master/Optimizer/OptimizeHelper.cs) / [Utilities.cs](https://github.com/hellzerg/optimizer/blob/master/Optimizer/Utilities.cs)；valleyofdoom [PC-Tuning](https://github.com/valleyofdoom/PC-Tuning)（§11.31–11.53）/ [research.md](https://github.com/valleyofdoom/PC-Tuning/blob/main/docs/research.md) / [TimerResolution](https://github.com/valleyofdoom/TimerResolution) / [AutoGpuAffinity main.py](https://github.com/valleyofdoom/AutoGpuAffinity/blob/main/AutoGpuAffinity/main.py)。

厂商文档：[MMCSS](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)、[中断亲和力](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/interrupt-affinity-and-priority)、[QPC/TSC/HPET 延迟](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)、[PERFBOOSTMODE](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-perf-state-engine-perfboostmode)、[电源调优（`PROCTHROTTLE*`/`CPMINCORES`/`DISTRIBUTEUTIL`/`RESP*`）](https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning)、[软实时设备指南](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/soft-real-time/soft-real-time-device)、[VBS 游戏性能声明（存档）](https://web.archive.org/web/20250818091118/https://support.microsoft.com/en-us/windows/options-to-optimize-gaming-performance-in-windows-11-a255f612-2949-4373-a566-ff6f3f474613)、[HAGS 机制](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/)。
数据与规格：[`Win32PrioritySeparation` 实测表](https://github.com/djdallmann/GamingPCSetup/blob/master/CONTENT/RESEARCH/FINDINGS/win32prisep0to271.csv)、[Ryzen 7 255 规格](https://www.notebookcheck.net/AMD-Ryzen-7-255-Processor-Benchmarks-and-Specs.1169506.0.html)。

## 4. 从 Winhance / Bloatynosy 源码里读到、明确不要照抄的

这两份定义文件（`GamingAndPerformanceOptimizations.cs` 218 KB、`WinRules.ini` 全量）里有些条目看似"游戏优化"，机制上却是负收益或自相矛盾：

| 条目 | 问题 |
|---|---|
| **关闭 VBS / HVCI**（`EnableVirtualizationBasedSecurity=0`、`HVCI\Enabled=0`、`Locked=0`） | 去掉内核池完整性与 CFG 保护；Winhance 自己的描述就写着 "reduces system security"。本机刻意保持开启（LoL 走 Vanguard） |
| **关闭 Storage Sense**（`AllowStorageSenseGlobal=0`，HKCU+HKLM 策略） | 与本项目的 `08=1`/`32=30` 直接冲突；`WinRules.ini` 自述"写成策略后设置界面会变灰" |
| **`WaitToKillServiceTimeout=1000`**（默认 5000） | 只给服务 1 秒刷盘，真实的数据丢失风险，不是"加快关机" |
| **`VisualFXSetting=3`** | 3 = "自定义"（2 才是"最佳性能"）；`WinRules.ini` 承认设置界面会显示"自定义"——单写 3 什么都不改变 |
| **`Win32PrioritySeparation=38`** | 被当作"提升前台优先级"，但按已测量的取值表，38 ≈ 默认值，36 反而**取消**了默认的 3:1 前台加成 |
| **StickyKeys `Flags`** | Winhance 写 `2`、Bloatynosy 写 `506`（默认 510）；写 2 会覆盖整个位域，两者互相矛盾 |
| **`Winlogon\DisableLockWorkstation=1`** | 直接去掉 Win+L 锁屏，是安全负收益 |
| **`SvcHostSplitThresholdInKB=3670016`** | 注释自己标注为 "Windows default"，纯 no-op |

---

<p align="right"><sub><a href="../README.md">← 目录</a> · <a href="./01-baseline.md">← 01 基线</a> · <a href="./03-system-tweaks.md">03 调优 →</a> · <a href="../../../README.md">笔记本</a></sub></p>