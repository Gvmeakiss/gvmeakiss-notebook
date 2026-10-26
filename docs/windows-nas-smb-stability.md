# 内网 NAS 连接：稳定性排查与优化记录

> 一条「感觉 NAS 不稳」的报障，最后定位到的**不是网络问题，而是睡眠唤醒后没人重连**。
> 本文记录诊断链条、可复用的判定方法，以及三件**做完才发现没收益、已回滚**的事。
>
> 全文脱敏：NAS 型号/主机名/内网地址/账号一律用 `<占位符>`，不出现真实值。

## 快速索引

| 你的症状 | 看这里 |
|---|---|
| NAS 时快时慢、大文件拷贝掉线 | [§6 先算天花板](#6-先算天花板再谈优化) |
| 睡一觉起来 NAS 盘符没了 | [§3 真因](#3-真因不是网络而是没有重连触发者) · [§4 解法](#4-解法用事件触发的计划任务重连) |
| 提权窗口里看不到 Z: 盘，以为映射坏了 | [§5 映射的会话与提权隔离](#5-映射按登录会话-提权级别隔离) |
| 计划任务报 `0x1` 但历史显示"成功" | [§8 计划任务的三个坑](#8-计划任务的三个坑) |
| 想抄判定标准 | [§9 判定标准](#9-判定标准什么算稳定) |

---

## 1. 症状与第一层误判

初始报障：*"NAS 连接速度慢、不稳定。"*

第一轮取到的证据看上去都指向硬件：

| 检查 | 结果 |
|---|---|
| 事件日志 `e2fnexpress` 事件 27 | **「网络链接已断开」47 次**（近 10 天） |
| 磁盘 `disk` 事件 51 | 23 次「传呼期间检测到一个错误」 |
| 网卡累计统计 | 丢包 0 / 错误 0 |

**最容易得出的错误结论**：「网卡在随机掉线，要换网卡/驱动/线」。

但有两个细节说明这个结论站不住：

- 网卡累计统计**零丢包零错误** —— 真随机掉线几乎不可能完全不留痕迹
- `disk` 事件指向 `\Device\Harddisk1\DR9…DR14`，而机器上**只有一块 NVMe** ——
  那块盘已经拔掉了，是 USB 存储反复插拔的历史记录

> **第一个方法教训**：先核对"这个报错指向的设备现在还存不存在"。
> 已拔掉的设备会在日志里长期留尸，计数看起来像活跃故障。

---

## 2. 用时间对齐，而不是猜

把两类事件按时间戳并排，结论立刻不同：

```
02:56:01  系统正在进入睡眠状态（原因: Application API）
02:56:01  Intel I226-V 网络链接已断开        ← 同一秒

22:29:44  系统正在进入睡眠状态
22:29:44  Intel I226-V 网络链接已断开        ← 同一秒

23:08:25  系统正在进入睡眠状态
23:08:25  Intel I226-V 网络链接已断开        ← 同一秒
23:08:28  网络已连接  名称: <路由器 SSID>     ← 唤醒后 3 秒重建
```

**47 次"断开"全部与睡眠/唤醒精确对齐。** 也就是说：

- 网卡和链路本身**健康**
- 「断开」是睡眠时网卡下电的**正常副作用**，不是故障

取证的 SQL 式做法（不需要猜，只要把两组事件拉出来对比时间）：

```powershell
# 睡眠/唤醒
Get-WinEvent -FilterHashtable @{
    LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=42,107
} -MaxEvents 20 | Select-Object TimeCreated, Id

# 网卡链路
Get-WinEvent -FilterHashtable @{
    LogName='System'; ProviderName='e2fnexpress'
} -MaxEvents 20 | Select-Object TimeCreated, Id, Message
```

> **第二个方法教训**：**断链事件的数量没有意义，它与什么事件对齐才有意义。**
> 先问"这些断开发生在什么时刻"，再问"它是不是故障"。

---

## 3. 真因：不是网络，而是"没有重连触发者"

对齐时间之后，问题收敛成一句话：**唤醒后没人把映射挂回来。**

验证链条（每一步都是实测）：

| 检查 | 结果 | 说明 |
|---|---|---|
| 唤醒后盘符还在吗 | `Test-Path 'Z:\'` → `False`，`Get-SmbMapping` → 空 | 确实丢了 |
| 持久映射记录 | `HKCU\Network\Z:` 存在 | 不是"没记住" |
| 凭据 | `cmdkey /list` 里 IP 与主机名两条都在 | 不是"没凭据" |
| 手动重连 | **1 秒成功** | 不是权限/凭据/网络问题 |
| **重连触发者** | **无** —— 启动脚本只在**登录时**跑一次 | ← 根因 |

也就是说：**持久映射 + 凭据都在，缺的只是"唤醒后执行一次重连"这件事。**

> 这类问题的通用形态：**状态是对的，事件没人接。**
> 排查时把"状态"与"触发器"分开看，能省掉大量无效检查。

---

## 4. 解法：用事件触发的计划任务重连

Windows 在每次网络就绪时都会写一条日志，用它当触发器即可，不需要轮询、不需要常驻进程：

| 项 | 值 |
|---|---|
| 日志 | `Microsoft-Windows-NetworkProfile/Operational` |
| 事件 ID | **10000**（网络已连接） |
| 延迟 | **15 秒**（等网络栈与对端都稳定，减少首次失败） |
| 动作 | `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<重连脚本>"` |
| 运行身份 | **`RunLevel=Limited`（非提权）** —— 见 §5 |
| 多实例 | `IgnoreNew` |
| 执行时限 | 5 分钟 |

**为什么用事件而不是定时轮询**：轮询要么太慢（唤醒后要等一个周期）、要么太费（频繁起进程）；
事件驱动只在状态真的变化时触发一次。

重连脚本本身必须**幂等**（已挂载就直接退出），因为事件可能连续触发多次：

```powershell
# 幂等骨架：已在就跳过；不在才等对端上线并重建
if (Test-Path 'Z:\') { exit 0 }
# ... 等待可达 → New-SmbMapping → 回读验证 → exit 0/1
```

**验收必须在正确的上下文里做**（§5），而且在目标盘符不存在时验证"能重建"，
而不是在它已经存在时验证"没报错"。

---

## 5. 映射按「登录会话 + 提权级别」隔离

这是本次花了最久才想通的一点，也是**最容易把正常行为误判成故障**的地方：

```
提权 PowerShell：  Test-Path 'Z:\' = False   Get-SmbMapping = 空
非提权上下文：     Test-Path 'Z:\' = True    Status = OK
两者 SessionId 相同（都是 3）
```

**这不是 bug，是设计**：UAC 分裂出的两个令牌各有独立的驱动器映射命名空间。

由此推出三条硬规则：

1. **验收"映射是否可用"必须在非提权上下文做** —— `explorer.exe` 也在非提权侧，
   它只认非提权侧建的映射
2. **计划任务要用 `RunLevel=Limited`**，映射才会建到 explorer 能看到的那一侧
3. **在提权窗口里看到"映射为空"不能作为失效证据** —— 那只是看错了命名空间

> 通用化：**Windows 上很多"对象"是按上下文隔离的**（会话、提权级别、宿主版本）。
> 拿到一个结果前，先确定"我在哪个上下文里看的"，否则会得出相反结论。

---

## 6. 先算天花板，再谈优化

报障是"慢"，所以先算上限，避免把物理限制当成软件问题：

| 链路 | 理论上限 | 说明 |
|---|---|---|
| 1 Gbps | **≈ 125 MB/s** | 125 是十进制商；实际还有协议开销，能到 110–118 已很好 |
| 2.5 Gbps | ≈ 312 MB/s | 同样按十进制换算 |

本机实测：

| 方向 | 实测 | 占 1 Gbps 上限 |
|---|---|---|
| 顺序写 | **89.2 MB/s** | 71% |
| 顺序读 | **106.0 MB/s** | **85%** |

**读到 85% 说明客户端侧已经没什么可榨的了。** 这时继续调软件参数是徒劳，
只有改链路速率（换 2.5G 交换机 / 换多通道拓扑）才有意义。

同时确认链路本身没有在丢数据：

```powershell
Get-NetAdapterStatistics -Name '<网卡名>' |
  Select-Object ReceivedBytes, ReceivedPacketErrors, ReceivedDiscardedPackets,
                OutboundPacketErrors, OutboundDiscardedPackets
# 期望：错误与丢弃全为 0
```

> **判据**：**先证明"已经接近上限"，再决定要不要优化。**
> 否则会把"1G 就是这么快"当成"NAS 有问题"，一直调一个不存在的故障。

---

## 7. 做过但无收益、已回退的

诚实记录三次"看起来该有用、实测没用"的尝试：

| 尝试 | 理论收益 | 实测 | 处置 |
|---|---|---|---|
| **关 SMB 签名** | 省 CPU、提吞吐 | 三轮 A/B：89.2/106.0 → 87.0/104.6 → 86.5/104.5，**无收益**，会话仍 `Signed : True` | **回滚**，并复核与备份一致 |
| **开巨帧 (Jumbo Frame)** | 减少包头开销 | 驱动 `*JumboPacket` 有效值列表为**空** —— 该驱动根本不提供这个档位 | 不可行 |
| **多通道 (SMB Multichannel)** | 两根线叠加带宽 | 需要 NAS 侧切"独立模式"并接第二根线；本次诉求是**稳定性**而非带宽，且链路已 85% 饱和 | 未采用（保留为选项） |

关于 SMB 签名有一条额外判断：`Signed : True` 是 Windows 11 的**安全默认**，
关掉它是降低安全性换取（实测并不存在的）性能 —— **不值得，也不建议**。

> **纪律**：任何"性能优化"都要有**同条件 A/B 实测**与**回滚步骤**，
> 并且优化后要**复核配置与备份一致**，避免"以为回滚了其实没回滚"。

---

## 8. 计划任务的三个坑

写这个重连任务时踩到的，全部实测：

### ① `0x1` 而任务历史显示"成功"

任务历史依次是 `100 已启动` → `110 已为用户启动` → `129 启动进程 PID` →
`200 操作已启动` → **`201 操作成功完成`** → **`102 任务成功完成`**，
而 `Get-ScheduledTaskInfo.LastTaskResult` 是 **`0x1`**。

进程确实起来了、1 秒后退出、什么都没做。根因是**脚本编码**：
用 UTF-8 **无 BOM** 保存、内含中文注释时，`powershell.exe`（5.1）按 ANSI 解码会解析失败，
而 `pwsh`（7）按 UTF-8 解码完全正常 —— **同一个文件，两个宿主一个能跑一个不能**。

**排查前提**：`TaskScheduler/Operational` 日志**默认是禁用的**，不先打开就只能靠猜：

```powershell
wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /e:true
```

**修法**：脚本**纯 ASCII**（首选）或存成 **UTF-8 with BOM**。
本仓库所有 `.ps1` 都声明 ASCII-only，并有一个检查器在提交前验证（见 `skills/windows-fresh-setup/scripts/check-script-hygiene.ps1`）。

### ② 任务的「参数」栏不通过 Shell 执行

写 `cmd /c "... > log 2>&1"` 时**重定向不会执行**，日志文件根本不生成，而任务照样报"成功"。
**日志必须由脚本自己写**（`Add-Content` / `[IO.File]::WriteAllText`）。

同理，任务里的**工作目录是 `C:\Windows\System32`**（实测），相对路径不可靠，一切路径写全。

### ③ `$LASTEXITCODE` 不被"进程内调用脚本"设置

`& .\child.ps1` 在当前会话内执行，`$LASTEXITCODE` **保留上一个子进程的值**。
实测后果：一个本该 FAIL 的校验被读成 PASS（更早的某次子进程调用留下了 0）。

**要拿子脚本的退出码只有两条路**：真的起子进程，或者**解析脚本自己输出的判定表**。

---

## 9. 判定标准：什么算"稳定"

| 检查对象 | ❌ 会误判的写法 | ✅ 正确判据 |
|---|---|---|
| 网卡"断开"事件 | 出现断开 ⇒ 链路故障 | **与什么事件对齐**：与睡眠/唤醒同秒即正常 |
| 累计丢包/错误 | 不看 | **必须为 0**；非 0 才需要查线/驱动/交换机 |
| 映射是否存在 | 在**提权**窗口里 `Test-Path` | 在**非提权**上下文验证（explorer 也在这侧） |
| 唤醒后映射 | 唤醒立即检查 | 等触发器延迟（本方案 15 秒 + 脚本内等待）后再判 |
| 计划任务成败 | 看历史"成功" | 看 `LastTaskResult`（`0x0` 才是成功） |
| 吞吐 | 凭感觉"慢" | **先算链路理论上限**，再看实测占多少 |
| 备份/回滚 | 改过就算回滚 | **回读配置与备份逐项比对** |

**三条元纪律**

1. **先证明"真的坏了"，再动手** —— 断链事件与睡眠同秒就不是故障
2. **状态与触发器分开看** —— 本次状态全对，缺的只是触发者
3. **验收要在目标上下文里做** —— 提权侧看不到非提权侧的映射

---

## 10. 可复现命令

```powershell
# 1) 链路与上限
Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, LinkSpeed, InterfaceDescription
Get-NetAdapterStatistics -Name '<网卡名>' |
  Select-Object ReceivedPacketErrors, ReceivedDiscardedPackets, OutboundPacketErrors

# 2) SMB 会话（注意：非提权上下文才看得到用户映射）
Get-SmbMapping
Get-SmbConnection | Select-Object ServerName, ShareName, Dialect, Signed, Encrypted
Get-SmbClientConfiguration | Select-Object EnableMultichannel, EnableLargeMtu

# 3) 睡眠/唤醒与断链的时间对齐
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=42,107} -MaxEvents 20 |
  Select-Object TimeCreated, Id
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='e2fnexpress'} -MaxEvents 20 |
  Select-Object TimeCreated, Id, Message

# 4) 重连任务自检
Get-ScheduledTask -TaskName '<任务名>' | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName '<任务名>' | Select-Object LastRunTime, LastTaskResult
Get-Content "$env:TEMP\<日志名>.log" -Tail 20

# 5) 吞吐实测（顺序写/读，文件大小 ≥ 100 MB 才有代表性）
#    写：Measure-Command { ... } + 文件大小 / 耗时；读同理
```

---

## 11. 脱敏声明

本文件不含：真实主机名、用户名、内网 IP、NAS 型号与地址、共享名、路由器 SSID、
凭据或令牌。所有具体值以 `<占位符>` 表示；网卡型号与事件 ID 属通用技术信息，予以保留。
