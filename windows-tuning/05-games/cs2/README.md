# Counter-Strike 2 优化

> 核显（Radeon 780M）跑 CS2 的实测配置。**不是"抄一堆启动项"，而是先定位瓶颈再逐项验证。**
>
> 免责：本文的硬件数据来自一次真实配置过程，作为**参考基线**；换机器请先跑
> [`scripts/check-cs2-readiness.ps1`](./scripts/check-cs2-readiness.ps1) 得到你自己的结论。

## 快速索引

| 我想… | 看这里 |
|---|---|
| 先知道这台机器能不能跑 | [§2 硬件评估](#2-硬件评估与瓶颈判定) |
| 直接做系统优化 | [§4 系统层优化](#4-系统层优化三项可回退) · [脚本](#脚本) |
| 游戏内怎么设 | [§5 游戏内设置](#5-游戏内设置按最贵到最便宜的顺序) |
| 启动项怎么填 | [§6 启动选项](#6-启动选项) |
| 卡顿/掉帧怎么排 | [§8 排错](#8-排错症状-原因) |
| 怎么撤销 | [§9 回滚](#9-回滚) |

---

## 1. 一句话结论

**能玩。** 在 **1080p + 低画质 + FSR** 下，Radeon 780M 大致 **60–100 FPS**，
足以喂满 60 Hz 屏幕。**瓶颈不在 CPU，而在"核显 + 显示器刷新率"。**

> **前置事实**：CS:GO 已于 2023-09 被 **CS2** 取代。Steam 里同一个 AppID `730` 现在下载的是 CS2，
> 安装目录仍叫 `Counter-Strike Global Offensive`，可执行文件是 `game\bin\win64\cs2.exe`。
> 网上大量 CS:GO 时期的控制台变量仍然通用。

---

## 2. 硬件评估与瓶颈判定

### 参考基线（一次实测配置）

| 部件 | 实测 | 对 CS2 的意义 |
|---|---|---|
| CPU | AMD **Ryzen 7 255**，8C/16T（Zen 4），3.8 GHz 基频 | 充裕，CS2 不构成瓶颈 |
| 显卡 | **Radeon 780M**（RDNA 3，12 CU）+ 2 GB 独享显存 | 约等于入门独显；1080p 低画质可用 |
| 内存 | **4 × 6 GB LPDDR5X-7500**，4 通道 | **核显最重要的指标**：多通道带宽充足（128-bit 位宽约 120 GB/s） |
| 存储 | NVMe SSD，68.84 GB 已被游戏占用 | 加载快，不是瓶颈 |
| 形态 | mini-PC，无电池 | 持续负载依赖散热；电源方案影响明显 |
| 显示器 | **3840×2160 @ 60 Hz** | ⚠ **真正的天花板** |

### 瓶颈判定的三步法（换机器也照着做）

```powershell
# ① 显示器刷新率上限 —— 超过它的帧数没有画面收益
Get-CimInstance Win32_VideoController | Select-Object CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate

# ② 显卡是核显还是独显；核显则看显存与内存通道
Get-CimInstance Win32_VideoController | Select-Object Name, @{n='显存MB';e={[math]::Round($_.AdapterRAM/1MB,0)}}
Get-CimInstance Win32_PhysicalMemory | Select-Object @{n='GB';e={[math]::Round($_.Capacity/1GB,0)}}, Speed, BankLabel

# ③ 内存是否多通道（核显单通道性能可能腰斩）
Get-CimInstance Win32_PhysicalMemory | Group-Object BankLabel | Measure-Object
```

**这台机器的判定**：CPU 富余 → GPU 是唯一约束 → **分辨率必须降到 1080p**，
并且因为屏幕只有 60 Hz，**帧数目标就是"稳定 ≥60、1% low 不要掉到 40 以下"**。

---

## 3. 优化前必做：确认游戏完整安装

```powershell
$steam = 'C:\Program Files (x86)\Steam'
$acf = Join-Path $steam 'steamapps\appmanifest_730.acf'
Get-Content $acf | Select-String 'StateFlags|SizeOnDisk|buildid'
```

`StateFlags = 4` 表示**完整安装**（若显示 `1026` 之类，说明还在下载/需要更新）。
`SizeOnDisk` 是实际占用（约 70 GB 量级）。

**另一个容易误判的点**：如果游戏目录里**没有** `game\csgo\cfg\cs2_video.txt`，说明
**游戏还从未启动过** —— 此时首次启动会用桌面分辨率（比如 4K），对核显是灾难，
**必须一进游戏就先改分辨率**。

---

## 4. 系统层优化（三项，可回退）

### 4.1 电源方案：切到「高性能」

Windows 11 默认把「高性能」方案**隐藏**了，很多机器上只有「平衡」一个可选。

```powershell
# 创建高性能方案（若不存在）
powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# 改名 + 设定（最小处理器状态用 80，不要一律 100）
powercfg /changename <新GUID> "高性能 (Game)"
powercfg /setacvalueindex <新GUID> SUB_PROCESSOR PROCTHROTTLEMIN 80
powercfg /setacvalueindex <新GUID> SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg /setacvalueindex <新GUID> SUB_PROCESSOR SYSCOOLPOL 1
powercfg /setactive <新GUID>
```

**为什么最小状态用 80 而不是 100**：100% 会让待机/轻载也维持最高频，温度与噪音上升；
80% 足以避免开局掉频，又不会常驻高功耗。**但不要降到 10–20%** —— 实测过会让"手感变肉"
（频率爬升有延迟，第一枪的响应变慢）。

**验证（必须回读十六进制值）**：

```powershell
powercfg /getactivescheme
powercfg /query <GUID> SUB_PROCESSOR 893dee8e-2bef-41e0-89c6-b55d0929964c   # 最小处理器状态
```

### 4.2 关闭 `cs2.exe` 的「全屏优化」

让游戏走**独占全屏**，绕过桌面合成器，降低输入延迟。

```powershell
$exe = 'C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe'
$key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
New-ItemProperty -Path $key -Name $exe -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' -PropertyType String -Force
```

> ⚠ **只能用 `New-ItemProperty` 写单个值。**
> 改用 `New-Item -Path $key -Force` 会**清空该键下所有已有值** ——
> 其他游戏的兼容性标记会一起丢失。改完务必对比"条目数是否只 +1"。

### 4.3 关闭后台录制、开启游戏模式

| 项 | 键 | 期望值 |
|---|---|---|
| GameDVR 策略 | `HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR` → `AllowGameDVR` | `0` |
| GameDVR 用户级 | `HKCU\System\GameConfigStore` → `GameDVR_Enabled` | `0` |
| 游戏模式 | `HKCU\Software\Microsoft\GameBar` → `AllowAutoGameMode` | `1` |

### 4.4 杀软排除（手动，无脚本接口）

实时扫描会在**加载地图、首次编译着色器**时抢 IO，表现为"进图先卡一下"。

> 在杀软客户端里把下面两个目录加入信任/排除：
> - `C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive`
> - `C:\Program Files (x86)\Steam\steamapps`

---

## 5. 游戏内设置（按"最贵到最便宜"的顺序）

> **顺序很重要**：先降最吃性能的项，每改一档测一次。一次性全拉最低会让你不知道
> 是哪一项起了作用，下次换机器也无法复用判断。

| 优先级 | 设置 | 建议值 | 说明 |
|---|---|---|---|
| **1（最关键）** | **分辨率** | **1920×1080** | 4K 下核显基本不可用；这是唯一"必须改"的一项 |
| **1** | 显示模式 | **全屏** | 配合 §4.2 关掉全屏优化 |
| **2** | 垂直同步 | **关闭** | 关了才有最低输入延迟 |
| **2** | 增强玩家对比度 | **开启** | 不耗性能，帮助看清敌人 |
| **3** | 多重采样抗锯齿 MSAA | 关闭 / 2x | 核显上非常贵 |
| **3** | 阴影质量 | **低** | 吃 GPU 且不影响看人 |
| **3** | 粒子细节 | 低 | 烟雾/火光时掉帧的主因之一 |
| **4** | 纹理质量 | 中 / 低 | 低显存时降低 |
| **4** | 着色器细节 | 低 | |
| **4** | 模型/贴图细节 | 中 | 太低反而影响辨识 |
| **5** | **AMD FSR** | 开启 → **平衡 / 性能** | **核显上收益最大的一招**，可从 60 拉到 80+ |
| — | 刷新率 | 跟显示器走（本例 60 Hz） | |

### 如果分辨率列表里没有 1080p

部分 4K 面板的 EDID 只上报 4K60 与几个老分辨率。两种办法：

1. **用 FSR**：保持 4K 输出、游戏内渲染降级（最省事，推荐）
2. **启动选项强制**：`-w 1920 -h 1080 -fullscreen`

---

## 6. 启动选项

Steam → 右键 CS2 → 属性 → 启动选项：

```
-novid -console +exec autoexec.cfg
```

| 参数 | 作用 |
|---|---|
| `-novid` | 跳过开场动画，少几秒等待 |
| `-console` | 启用控制台（排查用） |
| `+exec autoexec.cfg` | **执行自定义配置** —— CS2 **不会自动执行** `autoexec.cfg`，必须靠这条 |

`autoexec.cfg` 的位置：

```
<Steam>\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\autoexec.cfg
```

**建议只放性能与延迟相关、不影响手感与准心的项**：

```cfg
fps_max 120            // 略高于刷新率，避免核显满载与帧时间抖动
fps_max_ui 120         // 菜单界面限帧
r_dynamic 0            // 关闭动态光照，最省 GPU 的一档
cl_interp_ratio 1
cl_predict 1
cl_predictweapons 1
```

> **不要**往 autoexec 里塞灵敏度、准心、`viewmodel` 之类 —— 那是个人偏好，
> 而且会覆盖你以后在游戏里改的设置，造成"改了不生效"的困惑。

---

## 7. 预期帧数

| 场景 | 预期 | 备注 |
|---|---|---|
| 1080p 全低 + FSR 性能 | **80–110 FPS** | 空旷地图偏高 |
| 1080p 全低，无 FSR | 60–85 FPS | |
| 1440p 全低 | 45–65 FPS | 不建议 |
| 4K 任何设置 | 20–35 FPS | **不可用** |

**目标不是"平均帧最高"，而是"1% low 不低于 50"** —— 卡顿感来自最低 1% 帧。

---

## 8. 排错：症状 → 原因

| 症状 | 最可能的原因 | 怎么确认 |
|---|---|---|
| 一进游戏就 20 帧、画面糊 | 还在用桌面 **4K** 分辨率 | 看设置里的分辨率；`cs2_video.txt` 未生成 = 从未启动过 |
| 开局前 10 秒卡，之后正常 | 着色器编译 / 杀软扫描 | 第二次进同一张图还卡 → 排除着色器，查杀软排除 |
| 平均帧够但一阵一阵顿 | **1% low 太低**；核显满载降频 | 看 GPU 占用是否长期 99–100% + 温度；降画质或提高 fps_max 上限前的封顶值 |
| 帧数够但手感"拖" | 垂直同步开着；或没走独占全屏 | 关 VSync；确认 §4.2 标记存在 |
| 全屏切出去就闪退/黑屏 | 全屏优化与驱动冲突 | 先移除 §4.2 标记对比 |
| 每局随机掉线/瞬移 | 网络，不是性能 | 看 `net_graph` 的 loss/choke |
| 电脑整体卡、风扇狂转 | 电源方案仍是平衡/节能；散热不足 | `powercfg /getactivescheme` |

### 顺手确认"不是硬件坏了"

```powershell
# WHEA 硬件错误（应为空）
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 20

# 显卡 TDR（驱动超时重置，应为空）
Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101,4102} -MaxEvents 20

# 蓝屏转储（应为 0）
(Get-ChildItem C:\Windows\Minidump\*.dmp -EA SilentlyContinue).Count
```

---

## 9. 回滚

```powershell
# ① 电源方案退回平衡
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

# ② 恢复 cs2.exe 的全屏优化
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' `
  -Name 'C:\Program Files (x86)\Steam\steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe'

# ③ 删除 autoexec
Remove-Item '<Steam>\steamapps\common\Counter-Strike Global Offensive\game\csgo\cfg\autoexec.cfg'
```

或直接用脚本一键回退：

```powershell
pwsh -File scripts/apply-cs2-optimizations.ps1 -Revert -WhatIf   # 先看会撤销什么
pwsh -File scripts/apply-cs2-optimizations.ps1 -Revert           # 真正执行
```

---

## 脚本

| 脚本 | 用途 | 是否改系统 |
|---|---|---|
| [`scripts/check-cs2-readiness.ps1`](./scripts/check-cs2-readiness.ps1) | 只读体检：硬件、瓶颈、安装状态、现有设置、预期档位 | **否** |
| [`scripts/apply-cs2-optimizations.ps1`](./scripts/apply-cs2-optimizations.ps1) | 应用/回退三项系统优化（电源方案、独占全屏、autoexec） | 是，支持 `-WhatIf` 与 `-Revert` |

```powershell
# 只体检，不改任何东西
pwsh -File scripts/check-cs2-readiness.ps1

# 先预览要改什么
pwsh -File scripts/apply-cs2-optimizations.ps1 -WhatIf

# 应用（建议管理员运行：切换电源方案需要权限）
pwsh -File scripts/apply-cs2-optimizations.ps1

# 回退
pwsh -File scripts/apply-cs2-optimizations.ps1 -Revert
```

---

## 10. 脱敏声明

本文件不含：真实主机名、用户名、内网 IP、Steam 账号或 SteamID、设备序列号、凭据。
硬件型号、游戏 AppID 与目录名属通用技术信息，予以保留。
