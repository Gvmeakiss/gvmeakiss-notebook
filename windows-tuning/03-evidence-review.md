# Windows「优化」项目证据审查

> 配套 [win-ai-gaming-setup](../skills/win-ai-gaming-setup/SKILL.md)。那一份讲**怎么做**，这一份讲**为什么大多数流行做法不该做**。
>
> 方法：只读拉取 10+ 个项目的真实源码与文档（`.bat` / `.reg` / `.ps1` / `.cs`），
> **不执行**，逐条标注「有机制+有测量」「有机制无测量」「机制就是错的」。
> 每条结论都带出处链接；无法验证的明确标为不确定。

## 阅读顺序建议

| 你想知道 | 看哪一节 |
| --- | --- |
| 哪些 tweak 是真有用 | §1（有证据） |
| 哪些是神话、哪些有害 | §2（这个列表比 §1 长，是重点） |
| 我这个配置（APU/核显）该做什么 | §3 |
| 怎么证明改完有效 | §4（测量工具与协议） |

---
# Windows latency/"gaming optimization" tweaks — evidence review

Scope note: everything below comes from reading the actual scripts/docs (raw files / cloned trees), not README summaries. Repo files were downloaded read-only and never executed. Where a mechanism is documented but no measurement exists, it is labelled as such.

## 0. What the five nominated repos actually contain

| Repo | What it really is | Notable for this cluster |
|---|---|---|
| Hyyote/In-depth-Windows-tweaking + Hyyote/files- | Prose guide + ~70 loose `.bat/.reg/.ps1` files, many explicitly "experimental" | HPET DSDT patching, kernel variable patching via WinDbg, `bcdedit` wall, core-parking `.reg`, "Nuke" destructive script |
| AntonSiMal/Windows-Optimizer | A single 23 KB `UltimateWindowsOptimizer.bat` | `useplatformclock false`, `disabledynamictick yes`, `Win32PrioritySeparation=38`, `HwSchMode=2`, `bcdedit numproc`, Defender off, IPv6 off |
| luke-beep/all-about-windows | Early-beta notes repo; `docs/DATABASE.md` is a **bibliography + explainers** (interrupts/DPCs), not a settings catalogue | Useful as a pointer list (Bitsum power GUIDs, MSI docs), no mechanisms of its own |
| Disassembler0/Win10-Initial-Setup-Script | 3.9k-line `Win10.psm1` of privacy/service/scheduled-task tweaks with paired Enable/Disable functions | **No** HPET/MMCSS/timer/core-parking tweaks at all — the "reputable baseline" deliberately omits them |
| hellzerg/optimizer | C# WinForms app (`OptimizeHelper.cs`, `Utilities.cs`) with explicit revert paths | MMCSS `SystemResponsiveness=1`, HPET toggle, "UnlockAllCores", HAGS+GameMode bundle |

## 1. Techniques with real evidence (documented mechanism, and/or measurements)

### 1.1 Global timer resolution (`GlobalTimerResolutionRequests`) — measured
Setting: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel` → `GlobalTimerResolutionRequests`=dword:1 (Hyyote `tweaks/Pro1.bat`; valleyofdoom PC-Tuning §11.50; TimerResolution README).

What it does: restores pre-Windows-10-2004 *global* timer-resolution behaviour so one process raising `NtSetTimerResolution`/`timeBeginPeriod` affects the whole system, instead of only the caller.

Measured evidence (not folklore): PC-Tuning's author instrumented `Sleep(1)` with `NtQueryTimerResolution` + QPC on Windows 11 22H2 and got **~15.5 ms → ~1.5 ms** after the key, and confirmed via IDA/WinDbg that the kernel symbol `KiGlobalTimerResolutionRequests` **does not exist** in Windows 10 2004–22H2 (so the key is a no-op there). Windows 11 also drops the request when the calling window is minimised/occluded unless `SetProcessInformation(PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION)` is used.

Verify: `ClockRes` (current/min/max resolution) and `MeasureSleep` from valleyofdoom/TimerResolution (prints resolution + actual `Sleep(1)` delta). Note what is measured is *sleep pacing precision*, not input-to-photon latency — relevance is limited to sleep-based frame limiters/audio.

### 1.2 Micro-adjusting below/around 0.5 ms — measured, but only for pacing
PC-Tuning measured `Sleep(1)` deltas at requested resolutions: 1.000 ms → delta ≈0.999 ms; 0.500 ms → delta ≈0.496 ms; **0.507 ms → delta ≈0.012 ms**. 30+ testers reproduced 0.507 > 0.500 on most systems (some needed 0.6 ms; Win7 behaved differently). Mechanism: the requested period is quantised against the hardware clock, so the "maximum" resolution is not the most precise one.
Verify: `micro-adjust-benchmark.ps1` + MeasureSleep, under load, not idle.

### 1.3 VBS / HVCI (Memory Integrity) / VMP — vendor-acknowledged cost
Microsoft's own gaming-performance page states it has "seen that in some scenarios and some configurations of gaming devices there may be a performance impact with memory integrity and VMP on", and offers turning them off for gaming as a supported choice (with an explicit security warning). Note anticheat exceptions (Vanguard/FACEIT may *require* HVCI).
Verify: `msinfo32` → "Virtualization-based security" / "HVCI"; A/B a CPU-bound benchmark and a 1% low capture.
Caveat: no published per-title numbers in the sources read; treat the magnitude as unknown, the direction as vendor-confirmed.

### 1.4 Hardware-accelerated GPU scheduling (`HwSchMode`) — real mechanism, effect ≠ latency win
Mechanism documented by Microsoft's DirectX team: with WDDM 2.7+ the OS offloads most GPU scheduling (quanta management, context switching) to a GPU-based scheduling processor, removing the high-priority CPU scheduling thread; shipped as an **opt-in, off-by-default** feature.
Registry value used by all three tools: `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` → `HwSchMode`=2 (on) / 1 (off) (hellzerg `EnableGamingMode`/`DisableGamingMode`; Hyyote Pro1.bat; Anton's bat). The value name is not in Microsoft's public registry reference — mark the 1/2 mapping as *widely used and consistent across implementations, not officially documented*; confirm in Settings → Display → Graphics → "Hardware-accelerated GPU scheduling".
Evidence status: documented mechanism; **no measurement in any repo reviewed showing lower latency**. It is a prerequisite for some modern features (e.g. DLSS Frame Generation), which is the real reason to leave it on.

### 1.5 Interrupt affinity (`DevicePolicy` + `AssignmentSetOverride`) — documented API, measurement harness exists
Setting (per device): `HKLM\SYSTEM\CurrentControlSet\Enum\<HWID>\Device Parameters\Interrupt Management\Affinity Policy` → `DevicePolicy`=4 (`IrqPolicySpecifiedProcessors`), `AssignmentSetOverride`=REG_BINARY little-endian KAFFINITY mask. Microsoft documents exactly these values and their mapping to `u.Interrupt.AffinityPolicy`/`TargetedProcessors`; AutoGpuAffinity implements precisely this in `apply_affinity()` (`1 << cpu`, little-endian, then driver restart).
Evidence: PC-Tuning's method is to *measure first* — xperf DPC/ISR report (`bin/xperf-dpcisr.bat`, or `xtw`) to see which CPU services each module, then AutoGpuAffinity to benchmark every core for GPU/DXGK DPC-ISR time, then apply the best core; also verify ISR and its DPC land on the same CPU. No repo publishes population-level numbers; this is "measure your own box", not a universal tweak.
Gotcha worth flagging: Microsoft notes core parking may unpark cores *outside* an affinitised subset, so parking + affinity interact badly.

### 1.6 MMCSS `SystemResponsiveness` — documented, but the popular values are clamped
Microsoft documents: `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` → `SystemResponsiveness` = percentage of CPU reserved for low-priority tasks; **values not divisible by 10 are rounded down; values below 10 and above 100 are clamped to 20; 100 disables MMCSS.**
Consequence: the ubiquitous `SystemResponsiveness=0` (Hyyote-style tweak lists) and hellzerg's `=1` are **both clamped back to the default 20** — a documented no-op. hellzerg's "revert" writes **14**, which rounds to 10, i.e. it leaves the machine at a non-default value after "undo".
Also documented in the same page: for task subkeys, `GPU Priority` "is not yet used", `SFIO Priority` "is not used", and `Priority` "is always treated as 2" when `Scheduling Category` is `High` — so hellzerg's `GPU Priority=8`, `SFIO Priority=High`, `Priority=6` + `Scheduling Category=High` is largely inert.
And the deeper limit: a thread only joins an MMCSS task if the app calls `AvSetMmThreadCharacteristics` — there is no documented mechanism that auto-assigns the "Games" task to an arbitrary game process. Evidence for editing the Games task changing game behaviour: none found.

### 1.7 Power-management knobs with documented semantics (aliases verified)
From Microsoft's server power-tuning doc (aliases usable with `powercfg /setacvalueindex`):
- `PROCTHROTTLEMIN` / `PROCTHROTTLEMAX` — min/max processor performance state in %.
- `CPMINCORES` / `CPMAXCORES` — min/max % of cores that may be **unparked**; `CPMINCORES 100` disables parking. Parking's stated purpose is energy efficiency; MS notes the algorithm may unpark cores outside an affinitised subset.
- `DISTRIBUTEUTIL` — utility distribution; MS recommends disabling it for bursty/rapidly-migrating workloads.
- `PERFBOOSTMODE` (GUID `be337238-0d82-4146-a960-4f3749d470c7`, hidden) — 0 Disabled … 2 Aggressive; "determines how processors select a performance level when conditions allow boosting above nominal".
- `RESP*` (responsiveness override) — Windows raises a frequency floor when the DPC count per PPM check exceeds a threshold (default enable 10 / disable 5, floor 100%). This is the *existing* OS mechanism that already handles the "low utilisation but latency-critical" case; relevant to mini-PCs.
Also documented: the **High performance** plan "locks processors at the highest performance state (including turbo), all cores unparked… thermal output may be significant" — the exact trade-off that matters on a 45 W APU.
Evidence status: settings are real and observable (HWiNFO effective clocks, parked-core counts); **no measured gaming-latency benefit** for unparking found in any reviewed repo.

### 1.8 Microsoft's own narrow "real-time" service list (the only defensible "disable services" guidance)
Microsoft's soft-real-time device guide recommends disabling **only** SysMain, DPS, Audiosrv and Windows Update (plus idle states, `ThreadDpcEnable=0`, RSS ISRs to CPU0) — and states this is only valid for "an application and device custom-built for a specific purpose", that it "will open up your device to vulnerabilities", and that misapplying the RT-core CSP "results in system malfunction and requires reimaging". That is the ceiling of evidence for service stripping: a short, purpose-specific list, not a 200-service purge.

## 2. Myths, no-ops, or actively harmful on modern Windows

### 2.1 HPET / `useplatformclock` / `disabledynamictick` — mechanism inverted, guidance stale
- Hyyote's "settings for disabled HPET": `bcdedit /deletevalue useplatformclock`, `useplatformtick yes`, `disabledynamictick yes`; his README also says HPET must be off in BIOS. hellzerg ships the same pair as `DisableHPET()` and `useplatformclock true` as `EnableHPET()`; Anton sets `useplatformclock false` + `disabledynamictick yes`; Hyyote additionally patches the ACPI **DSDT** (GRUB method or a test-signed driver) to remove the HPET device.
- Why this is backwards/folklore: since Windows 8, Windows uses the invariant TSC as the QPC basis and only falls back to HPET/ACPI-PM when the TSC is unsuitable. Microsoft documents that platform timers "have higher access latency than the TSC and are shared between multiple processors", with per-call QPC cost "in the vicinity of 0.8–1.0 microseconds" vs tens–hundreds of cycles for TSC, and requires a kernel transition. Forcing the platform clock therefore moves timing onto the *slower* device; `disabledynamictick` disables dynamic-tick/coalescing behaviour (power/thermal cost) and is a debug switch, not a latency optimisation.
- Notably, the most evidence-oriented guide in this space (PC-Tuning) contains **no** `useplatformclock`/`disabledynamictick`/HPET section at all.
- Evidence for benefit: none. Evidence for cost: documented TSC-vs-platform-timer latency gap; DSDT patching additionally endangers firmware/ACPI assumptions and (per Hyyote himself) breaks with many anticheats.

### 2.2 "Disable core parking" `.reg` files — probably a no-op, possibly inverted
Hyyote's `tweaks/Disable core parking.reg` and hellzerg's `Utilities.UnlockAllCores()` write **`ValueMax=0` and `ValueMin=0`** to
`HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-…\0cc5b647-c1df-4637-891a-dec35c318583` (CPMINCORES) — i.e. the **PowerSettings metadata tree** that defines a setting's allowed range/visibility, *not* the active per-scheme value (which lives under `…\Control\Power\PowerSchemes\…` and is read by `powercfg /q`). Two problems: (a) the running plan is not obviously changed at all; (b) if it does clamp the range, clamping CPMINCORES to **0** means "minimum 0 % of cores unparked", the opposite of "disable parking". The correct, documented method is `powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100` + `powercfg /setactive`. (Semantics of ValueMin/Max are from the PowerSettings schema; I did not run either file — flagged as *likely broken* rather than proven broken.)

### 2.3 Mass service/component disabling — documented breakage, no measured latency win
- Hyyote's `Nuke` README lists 18 phases that delete services, ETW autologgers, event-log channels, WER, `wevtutil`/`perfmon`/`taskmgr.exe`, and replace `wer.dll` with a stub — "No backups… irreversible". Whatever the privacy merit, none of it is a latency mechanism, and removing ETW/eventing destroys the very tooling (`xperf`, WPR, PresentMon traces) needed to verify latency.
- Microsoft's own doc set says the *opposite* of the folklore: a handful of services matter for a dedicated RT device; everything else is not a scheduler-level factor. PC-Tuning's rule is to check dependencies (`sc EnumDepend`) before disabling anything, and documents that disabling Windows Update breaks the Store.
- Where disabling *is* defensible: WSearch/SysMain (background I/O/CPU), Defender real-time scanning on game folders — but these are I/O/CPU-noise reductions, not scheduler-latency fixes, and no reviewed repo quantifies them.
- On a mini-PC also note: disabling `DiagTrack` etc. is harmless, but disabling `WpnService`, `StateRepository`, AppX/ClipSVC on Windows 11 is a known breakage pattern (Hyyote's own README concedes Win11 can only go to ~31 services vs ~22 on Win10).

### 2.4 `Win32PrioritySeparation` magic numbers
Hyyote sets **36** (0x24); Anton sets **38** (0x26). The measured kernel-read table (djdallmann, cross-checked in WinDbg by PC-Tuning) gives: default 2 → Shorter/Variable, FG 18 / BG 6 (3:1); **36 → Shorter/Variable, FG 6 / BG 6 (no foreground boost)**; 38 → Shorter/Variable, 18/6; 40 → Shorter/Fixed, 18/18. So 36 *removes* the foreground quantum boost, and 38 is effectively the default. Values >0x3F just alias lower values because the kernel reads only 6 bits. Evidence of a game-responsiveness benefit: none in any repo; the "38 = short, fixed, 3:1" claim repeated across tweak lists contradicts the measured table.

### 2.5 Live kernel patching (Hyyote `kernel/…settings.txt`)
`ed nt!KiQuantumEnd 0`, `ed nt!PspComputeQuantum 0`, `ed nt!ExpTimerResolutionCount 0`, `eb nt!KiIdleLoop 90`, zeroing `KeFeatureBits`, `HvlEnlightenments`, etc. — via LiveKD/WinDbg against a *running* kernel. Non-persistent, unsupported, and directly disables scheduler/timer accounting the OS depends on. No measurements, no revert path; several of these (`PspComputeQuantum=0`, `KiIdleLoop` patch) are plausible instant-hang material. Classify as experimentation, not tuning.

### 2.6 C-state 0 / "disable idle states" on a low-power APU
Microsoft lists `IdleDisable` for soft-real-time devices, and PC-Tuning documents the mechanism (forces C0) while explicitly recommending against it for most users: higher temperature/power, interference with boost algorithms (PBO/Turbo), and worse single-thread performance with SMT on. On a 45 W Ryzen 7 255 sharing one power/thermal budget with a 780M iGPU this is the clearest "hurts more than it helps" case.

### 2.7 Assorted inert or risky `bcdedit` items
`numproc %NUMBER_OF_PROCESSORS%` (Anton) sets the limit to the current count — a no-op; `nx alwaysoff`, `hypervisorlaunchtype off`, `disableelamdrivers yes`, `tpmbootentropy forcedisable`, `isolatedcontext no`, `vsmlaunchtype off` (Hyyote) trade security/reliability (and HVCI availability) for no measured latency gain. `useplatformtick yes` + `disabledynamictick yes` also raise idle power draw — counterproductive on a mini-PC.

### 2.8 Game Mode — genuinely uncertain
PC-Tuning's only claim is that Game Mode "can interfere with process and thread priority boosts" (reproducible with the PerfMon thread-priority experiment from *Windows Internals*) and that it suppresses Windows Update/notifications; it advises A/B testing rather than a verdict. hellzerg bundles `AutoGameModeEnabled=1` with HAGS under "EnableGamingMode", which conflates two unrelated features. Treat as neutral/uncertain, not as a tweak.

### 2.9 MSI mode — real mechanism, real BSOD risk, payoff unproven
MSI replaces line-based interrupts with memory writes; PC-Tuning documents it as faster in principle, able to resolve IRQ sharing, enabled per device via MSI Utility/GoInterruptPolicy, verified by a **negative IRQ** after reboot — and warns it can BSOD (e.g. stock Win7 SATA driver) and that vendors sometimes intentionally ship MSI disabled (NVIDIA per-architecture). No measurement of frame-time/latency improvement in the sources read. On an iGPU (interrupts on-die, no PCIe hop) the expected upside is smaller than on a dGPU.

## 3. Highest-value tweaks for a Ryzen 7 255 + Radeon 780M mini-PC
Platform facts used: Ryzen 7 255 = Hawk Point, Zen 4, 8C/16T, 16 MB L3, Radeon 780M (12 CU, ≤2.6 GHz), 45 W TDP (35–54 W configurable), DDR5-5600/LPDDR5x-7500, no NPU enabled.

1. **Turn off VBS/HVCI (+ Virtual Machine Platform) if anticheat allows.** Only vendor-acknowledged, CPU-side cost in this whole list; on a power-limited APU it also returns thermal headroom. Verify with `msinfo32`; re-check after any BIOS virtualisation change. Keep it on if you play Vanguard/FACEIT titles.
2. **Keep the Balanced plan; do not pin the CPU at 100 %.** Skip `PROCTHROTTLEMIN 100`, skip "Ultimate Performance", skip C-state-0 disabling. Instead set a modest AC floor (e.g. `PROCTHROTTLEMIN 5`), leave `PERFBOOSTMODE` at default, and verify in HWiNFO that the package is not thermally/STAPM-throttling while gaming. Rationale is the documented trade-off (High Performance locks turbo and "thermal output may be significant") plus the shared CPU/iGPU budget. This is the single biggest *stability-preserving* lever on a 45 W box.
3. **Cap frame rate just under the sustained limit** (in-game limiter, or RTSS with hybrid wait) rather than chasing timer resolution. PC-Tuning's framerate-limit section is the practical recommendation here: lower, steadier power draw → less throttling → better 1 % lows. Seconds saved per frame beat microseconds of timer precision.
4. **Timer resolution: only if measurably broken, and prefer per-process.** `GlobalTimerResolutionRequests=1` is Windows 11/Server 2022+ only, restores global 0.5 ms at the cost of waking idle cores more often (power/heat/fan noise on a mini-PC). Measure first with `ClockRes` + `MeasureSleep`; if the game's own limiter is fine at default resolution, change nothing. If you do enable it, re-check that the process is not minimised (Win11 revokes the request) — or use `PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION`.
5. **Measure interrupt/DPC placement before touching affinity; leave MSI mode alone on the iGPU.** Run `xperf -on PROC_THREAD+LOADER+DPC+INTERRUPT` (or `xtw`) during gameplay, and AutoGpuAffinity if GPU DPC/ISR times look noisy or land on a busy core. Apply `DevicePolicy=4` + `AssignmentSetOverride` only for a measured win, keep the ISR and its DPC on the same CPU, and remember parking may unpark cores outside the mask. Do not enable MSI mode on the 780M "because guides say so": BSOD risk, no measured benefit for an on-die GPU.

Low-risk hygiene that is not a latency mechanism but removes jitter sources: GameDVR/background recording off (`HKCU\System\GameConfigStore\GameDVR_Enabled=0`, `AppCaptureEnabled=0`), native resolution + no GPU scaling, unnecessary USB/audio devices disabled, and a clean driver install. None of these has published frame-time numbers in the sources reviewed.

Deliberately excluded from the recommendation set: HPET/`useplatformclock`/`disabledynamictick`, MMCSS `SystemResponsiveness`, core-parking `.reg` hacks, `Win32PrioritySeparation` numbers, mass service disabling, kernel patching, C-state-0 forcing.

## 4. Sources
- Hyyote guide: https://github.com/Hyyote/In-depth-Windows-tweaking/blob/main/README.md
- Hyyote scripts: https://github.com/Hyyote/files-/blob/main/tweaks/Pro1.bat · https://github.com/Hyyote/files-/blob/main/tweaks/settings%20for%20disabled%20HPET.bat · https://github.com/Hyyote/files-/blob/main/tweaks/Disable%20core%20parking.reg · https://github.com/Hyyote/files-/blob/main/tweaks/Nuke/README.md · https://github.com/Hyyote/files-/blob/main/tweaks/HPET%20patch/README.md · https://github.com/Hyyote/files-/blob/main/tweaks/HPET%20patch/GRUB%20method/Setup-GRUB-HPET.ps1 · https://github.com/Hyyote/files-/blob/main/kernel/Usage%20and%20personal%20settings.txt
- AntonSiMal: https://github.com/AntonSiMal/Windows-Optimizer/blob/main/UltimateWindowsOptimizer.bat
- luke-beep: https://github.com/luke-beep/all-about-windows/blob/main/docs/DATABASE.md
- Disassembler0: https://github.com/Disassembler0/Win10-Initial-Setup-Script/blob/master/Win10.psm1
- hellzerg: https://github.com/hellzerg/optimizer/blob/master/Optimizer/OptimizeHelper.cs · https://github.com/hellzerg/optimizer/blob/master/Optimizer/Utilities.cs
- valleyofdoom/PC-Tuning: https://github.com/valleyofdoom/PC-Tuning (README §11.31–11.53) · https://github.com/valleyofdoom/PC-Tuning/blob/main/docs/research.md
- valleyofdoom/TimerResolution: https://github.com/valleyofdoom/TimerResolution
- valleyofdoom/AutoGpuAffinity: https://github.com/valleyofdoom/AutoGpuAffinity/blob/main/AutoGpuAffinity/main.py
- MMCSS: https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service
- Interrupt affinity: https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/interrupt-affinity-and-priority
- QPC/TSC/HPET latency: https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps
- PERFBOOSTMODE: https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-perf-state-engine-perfboostmode
- Power tuning (PROCTHROTTLE*, CPMINCORES, DISTRIBUTEUTIL, RESP*): https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning
- Soft real-time device guidance: https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/soft-real-time/soft-real-time-device
- Microsoft gaming/VBS statement (archived): https://web.archive.org/web/20250818091118/https://support.microsoft.com/en-us/windows/options-to-optimize-gaming-performance-in-windows-11-a255f612-2949-4373-a566-ff6f3f474613
- HAGS mechanism: https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/
- Win32PrioritySeparation measured table: https://github.com/djdallmann/GamingPCSetup/blob/master/CONTENT/RESEARCH/FINDINGS/win32prisep0to271.csv
- Ryzen 7 255 specs: https://www.notebookcheck.net/AMD-Ryzen-7-255-Processor-Benchmarks-and-Specs.1169506.0.html
