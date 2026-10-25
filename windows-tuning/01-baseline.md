# Windows 基线：起点、环境与工具链

两台真机（`windows-tuning/01-env-setup-win10.md` 的 Win10 非管理员机、`windows-tuning/02-env-audit-win11.md` 的 Win11 管理员机）
的环境事实合成一份基线：起点类型 → 最终环境 → 软件清单 → 验收判据 → 边界。
工具与判据统一取自 [`skills/win-ai-gaming-setup`](https://github.com/Gvmeakiss/gvmeakiss-notebook/tree/main/skills/win-ai-gaming-setup)：
方法论与陷阱速查在 `SKILL.md`，人读说明在 `README.md`，入口 `scripts/setup.ps1`，七阶段 `check` / `dev` / `apps` / `drivers` / `tune` / `link` / `verify`。
单件脚本（同在 `scripts/`）：`bootstrap.ps1`（无 git 自举）· `audit-env.ps1` · `fix-env.ps1` · `setup-langs.ps1` · `install-portable.ps1` ·
`snapshot-services.ps1` / `compare-services.ps1` · `set-app-associations.ps1` · `reset-failed-devices.ps1` · `diagnose-ime.ps1` · `check-software.ps1` · `check-script-hygiene.ps1` · `clean-orphan-associations.ps1` · `verify-env.ps1`。
仓库：[Gvmeakiss/gvmeakiss-notebook](https://github.com/Gvmeakiss/gvmeakiss-notebook)

## 这台机器是什么状态

| 起点类型 | 权限 | 前提 | 能做与不能做 |
|---|---|---|---|
| **空环境** —— Windows 10 Pro 22H2（build 19045）；无任何语言环境，无 winget / choco；Git 2.56、7-Zip 26.04、Scoop v0.6.0 已装但 shims 不在 PATH | **非管理员**：不能提权，不能装机器级 MSI | 直连可用；`nodejs.org`、`static.rust-lang.org` 有 DNS 污染；`github.com:22` 被阻断 | 能做：用户级 Scoop 装 8 种语言工具链（Python / Node / Go / Rust / Java / .NET / C·C++，含 CMake）；便携软件装 `~\Apps`（删文件夹即卸载）；HKCU 写文件关联；`gh auth login` 设备码认证。不能做：机器级 MSI（VC++ 运行库、WinFsp）、脚本设默认程序、`drivers` 与 `tune` 阶段 |
| **"已优化"机** —— Windows 11 Pro（build 26300）；单块 NVMe、无电池小型台式机 | **管理员** | 工具链由 WinGet + 官方安装器建成，**无 Scoop**；网络直连 | 能做：`tune` 全量（先快照）、`drivers -InstallDrivers`、`reset-failed-devices -Reset`、恢复 7 个非遥测计划任务、清传递优化缓存（表观 13.4 GB，实测净增 5.1 GB）。不能做：脚本设默认程序（提权不改变 `UserChoice` 的 Deny + Hash）；启用 `UpdateOrchestrator` 三个任务（任务 XML `<Enabled>false</Enabled>`、`BUILTIN\Administrators` 只读）；直接写 `HKCU\...\CurrentVersion\Search` 的 `BingSearchEnabled`（内核层拒写，改走策略键） |

## 最终环境

### 工具链

| 工具 | 版本 | 验证命令 |
|---|---|---|
| PowerShell 7 | 7.6.6（Win10）· 7.6.7（Win11） | `$PSVersionTable.PSVersion` |
| Python / pip | 3.14.8 / 26.2.1（Win10）· 3.14.7（Win11） | `python --version`；`pip --version` |
| Node.js / npm | 26.11.1 / 11.20.0（Win10）· 24.20.0 / 11.19.0（Win11） | `node -v`；`npm -v` |
| Go | 1.27.2（Win10）· 1.27.0（Win11） | `go version` |
| Rust / Cargo | 1.99.0，host `x86_64-pc-windows-gnu` | `rustc -Vv`；`cargo -V` |
| Temurin JDK | 21.0.12.1 LTS（Win10） | `java -version` |
| .NET SDK | 10.0.401 | `dotnet --version` |
| GCC / G++ | 16.2.0（MinGW-w64，UCRT + POSIX + SEH） | `gcc -dumpfullversion -dumpversion` |
| CMake | 4.4.4 | `cmake --version` |
| GDB / GNU Make | 17.2 / 4.4.1（Win10） | `gdb --version`；`make --version` |
| Git / gh / 7-Zip | 2.56.0（Win11 为 2.56.0.windows.2）/ 2.102.0（Win10）/ 26.04 | `git --version`；`gh --version`；`7z i` |
| uv | 0.13.0（Win11） | `uv --version` |
| VS Code / Windows Terminal | 1.141.0（Win11）/ 已装，未记版本 | `code --version`；`Get-Command wt` |

> **Rust 的目标平台是 `x86_64-pc-windows-gnu`，不是 MSVC。** MSVC 工具的 MSI 安装需要管理员权限，非管理员机上不可用；
> GNU 目标直接复用已装的 MinGW-w64。GNU 目标链接 proc-macro 需要 `dlltool`，它在 MinGW 的 binutils 里。
> 版本号只作线索：`verify` 阶段对 7 条语言链各做一次**真实编译运行**（`cpp` 一条同时覆盖 C 与 C++），能打印 `--version` 不等于能编译。

### 镜像源

| 生态 | 源 | 生效方式 | 验证 |
|---|---|---|---|
| pip | 清华 `pypi.tuna.tsinghua.edu.cn` | `%APPDATA%\pip\pip.ini` | `pip config list` |
| npm | `registry.npmmirror.com` | npm 用户配置（`NPM_CONFIG_REGISTRY`） | `npm config get registry` |
| Go | `goproxy.cn` | `go env -w` | `go env GOPROXY` → `https://goproxy.cn,direct` |
| Cargo | `rsproxy.cn` | `~/.cargo/config.toml` | `Get-Content ~/.cargo/config.toml` |
| rustup | `rsproxy.cn` | `RUSTUP_DIST_SERVER`（用户级） | `$env:RUSTUP_DIST_SERVER` |
| NuGet | nuget.org 主 + 华为云备 | `%APPDATA%\NuGet\NuGet.Config` | `dotnet nuget list source` |
| HuggingFace | `hf-mirror.com` | `HF_ENDPOINT`（用户级） | `$env:HF_ENDPOINT` |

> `-Phase dev` 收尾逐项回读真实值；工具不在 PATH 时整段跳过，不写硬编码的"已生效"。
> `scripts/audit-env.ps1` 另对 6 个端点做并发 HEAD 可达性检查（pypi-tuna / npmmirror / goproxy.cn / rsproxy / nuget-huawei / github），单个超时 12 s。

### 环境变量与 PATH

新开终端（不是已运行的窗口）后必须同时成立：

| 变量 / 项 | 值 | 验证 |
|---|---|---|
| `JAVA_HOME` | `~\scoop\apps\temurin21-jdk\current` | `$env:JAVA_HOME` |
| `DOTNET_ROOT` | `~\scoop\apps\dotnet-sdk\current` | `$env:DOTNET_ROOT` |
| `GOPATH` / `GOPROXY` | `C:\Users\<你>\go` / `https://goproxy.cn,direct` | `go env GOPATH`；`go env GOPROXY` |
| `RUSTUP_DIST_SERVER` | `https://rsproxy.cn` | `$env:RUSTUP_DIST_SERVER` |
| `NPM_CONFIG_REGISTRY` / `PIP_INDEX_URL` | 对应镜像地址 | `$env:NPM_CONFIG_REGISTRY`；`$env:PIP_INDEX_URL` |
| `HF_ENDPOINT` | `https://hf-mirror.com` | `$env:HF_ENDPOINT` |
| `PYTHONUTF8` | `1` | `$env:PYTHONUTF8` |
| PATH | 含 `~\scoop\shims`、`~\.cargo\bin` 与 `addToPath` 的便携目录（`mpc-be64` / `notepad++` / `rclone`） | `$env:PATH -split ';'` |
| `python` | 命中真解释器，不是 `WindowsApps` 下 0 字节的 Store 存根 | `(Get-Command python).Source` |
| `python3` | 解析到真 Python，不是 `WindowsApps` 的 0 字节存根；部分 scoop 清单只建 `python3`，用户 PATH 中真目录排在 `WindowsApps` 之前 | `python3 --version`；`(Get-Command python3).Source` |
| git 长路径 | `core.longpaths=true`；`LongPathsEnabled=1` | `git config --get core.longpaths`；`reg query "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled` |

> 变量与配置文件并存时以工具回读值为准（`pip config list` / `npm config get registry`）。
> `PYTHONUTF8=1` 只在本机生效：代码仍要显式 `encoding='utf-8'`，CI 和别人的机器不会设它。
> 环境变量变更不影响已运行进程，GUI 父进程的环境可能早于配置；脚本按机器级 + 用户级重建 PATH：
> `[Environment]::GetEnvironmentVariable('Path','Machine')` 与 `...('Path','User')` 拼接。

## 软件清单

`skills/win-ai-gaming-setup/apps.json` 共 **13 条**：2 个压缩工具 + 5 个便携软件 + 6 个 VC++ 运行库。
`-Phase apps` 按清单全量安装：便携条目必需 `sha256`（缺哈希直接拒绝，`-AllowUnverified` 才放行），
`winget` 条目按 `verifyPath` 回读文件后才算装上 —— `winget` 的退出码本身不算证据。

| 名称 | 来源 | 校验方式 |
|---|---|---|
| 7-Zip | `winget` `7zip.7zip` | 回读 `%ProgramFiles%\7-Zip\7z.exe` |
| WinRAR | `winget` `RARLab.WinRAR` | 回读 `%ProgramFiles%\WinRAR\WinRAR.exe`；40 天试用后带弹窗可用 |
| JPEGView | GitHub `sylikc/jpegview` v1.3.46 zip | SHA256 → 回读 `JPEGView64\JPEGView.exe`（压缩包有三个顶层目录，路径不可扁平化） |
| MPC-BE | GitHub `Aleksoid1978/MPC-BE` 1.9.1 x64 7z | SHA256 → 回读 `mpc-be64.exe` |
| Notepad++ | GitHub `notepad-plus-plus` v8.9.8.1 portable x64 | SHA256 → 回读 `notepad++.exe`（便携版，配置留在程序目录） |
| TrafficMonitor | GitHub `zhongyang219` V1.86 x64 | SHA256 → 回读 `TrafficMonitor.exe`；落盘 `presets/TrafficMonitor.config.ini` 与 `global_cfg.ini`（便携模式） |
| rclone | GitHub `rclone` v1.75.1 windows-amd64 | SHA256 → 回读 `rclone.exe` |
| VC++ 2010 x86 | `winget` `Microsoft.VCRedist.2010.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr100.dll` |
| VC++ 2010 x64 | `winget` `Microsoft.VCRedist.2010.x64` | 回读 `%SystemRoot%\System32\msvcr100.dll` |
| VC++ 2012 x86 | `winget` `Microsoft.VCRedist.2012.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr110.dll` |
| VC++ 2012 x64 | `winget` `Microsoft.VCRedist.2012.x64` | 回读 `%SystemRoot%\System32\msvcr110.dll` |
| VC++ 2013 x86 | `winget` `Microsoft.VCRedist.2013.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr120.dll` |
| VC++ 2013 x64 | `winget` `Microsoft.VCRedist.2013.x64` | 回读 `%SystemRoot%\System32\msvcr120.dll` |

便携条目在 `apps.json` 里的 5 个 SHA256 实测值：

```
ba71d5983b6c9e2dc55abbec0da53be54e67cf3251d6e9d2d8be82fe7d85bbe5  JPEGView_1.3.46.zip
d9ef12c0492e420f5c5650a8102d01f7a2dcf34d2151ca3e2fb8323d0984c74a  MPC-BE.1.9.1.x64.7z
beddf5548e75c97930d1575ba1c7d113e6e2b33d0a200310e734ca08e225f414  npp.8.9.8.1.portable.x64.zip
948ddc12cc582e8cf0b7b32e0064544f6f711265a7671c2e47343a6a0ff4908e  TrafficMonitor_V1.86_x64.zip
200eb602c126d82aa38b51e0f6b9ae837473ff99b51278d3f6f837574c494d6e  rclone-v1.75.1-windows-amd64.zip
```

> 便携软件不进"应用和功能" / 系统应用列表，只存在于 `~\Apps`；盘点必须扫目录，不能只看系统列表。
> 6 个 VC++ 运行库按 x86 / x64 分开列：64 位游戏拿不到 32 位 DLL；它们不属于 Windows 本身，缺了通常表现为游戏弹"缺少 msvcr1xx.dll"。

## 验收基线

```powershell
pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase verify   # 七阶段之一
pwsh -File skills/win-ai-gaming-setup/scripts/verify-env.ps1            # 等价单件脚本
```

**判据：97 项 / 0 失败，退出码 0。** 输出形态为每组一行 `[OK] <组> <通过>/<总数> checks passed`，
末尾 `total: <N> checks, 0 failed, <K> informational`；`informational` 不计入失败。
组共 15 个，与汇总输出一一对应：`hygiene` · `tweaks`（含 MMCSS 驱动是否 `RUNNING`、tune 值存活） ·
`python` / `node` / `go` / `rust` / `java` / `dotnet` / `cpp` · `archives` · `git` / `gh` / `ssh` · `system` · `runtimes`。

| 对象 | 命令 | 期望 |
|---|---|---|
| 软件清单 | `setup.ps1 -Phase apps` | 每条先报 `verified: <真实路径>`，收尾 `all selected apps installed and verified (13/13)` |
| 系统调优值 | `setup.ps1 -Phase verify` 的 `tweaks` 组 | 值**缺失**判 FAIL（累积更新是删值，不是改值）；MMCSS 必须 `sc query MMCSS` 为 `STATE: 4 RUNNING` |
| 只读盘点 | `check-software.ps1 -PortableRoot $env:USERPROFILE\Apps` | `declared apps: 13/13 present`；缺失项单独一行 `missing: <名称>` |
| 脚本体检 | `check-script-hygiene.ps1` | `0 FAIL, 0 WARN`（PS 7 与 PS 5.1 双宿主解析） |
| 文件关联 | `setup.ps1 -Phase link`（加 `-RegisterAssociations` 才写 HKCU） | 每个 `assoc` 扩展名给出候选 ProgID，并点名仍需手动点一次的类型 |

`-Phase apps` 的 13 条与 `verify` 的 `runtimes` 组是两套判据：前者证明装上了，后者证明运行库在系统路径里能被加载。

> **先重启再验收** —— PATH、输入法栈、MMCSS 驱动都在登录时重建；`sc start` 返回 1341 只说明引导期驱动未起，重启后直接 `RUNNING`。
> 同一会话里重复验收不是证据。`-WhatIf` 只打印将做什么，不落盘、不装包。

## 已知边界

| 不覆盖 / 做不到 | 事实与判据 |
|---|---|
| 无管理员权限（Win10 机） | 机器级 MSI 装不上：VC++ 运行库、WinFsp（`rclone mount`）、`drivers` 与 `tune` 阶段都在权限之外。便携包 + 用户级 Scoop 是这条路线的上限 |
| 非 Windows 平台 | 脚本仅 Windows + PowerShell 7（5.1 能跑，但计划任务用 5.1 调用，故 `.ps1` 必须 ASCII-only）；POSIX 权限位断言在 Windows 恒为 `0o666`，跨平台测试按平台条件执行 |
| 缺 Scoop 的机器 | `dev` 阶段的自动安装不可用；`verify-env.ps1` 对 `scoop` 0 处引用 —— 验收与故障处置完整可用。已由 WinGet 配好的机器不补装 Scoop：同一工具两套安装会互相抢 PATH |
| 默认程序 | 改不了：`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<扩展名>\UserChoice` 有显式 `Deny SetValue` ACE（压过 `Allow FullControl`）+ `Hash`。官方 `IApplicationAssociationRegistration`（CLSID `591209c7-767b-42b2-9fba-44ee4615f2c7`）的 `SetAppAsDefault` 在 Win10 返回 `0x80070002`，`QueryAppIsDefault` 正常。脚本只能让程序出现在"打开方式"候选里，默认仍需手动点一次 |
| 便携软件可见性 | 不进"应用和功能"；卸载后 ProgID / `RegisteredApplications` / `Capabilities` 残留由 `clean-orphan-associations.ps1` 清，`UserChoice` 指向已删程序时双击打不开 |
| 服务与计划任务 | 不禁用任何服务；`UpdateOrchestrator` 三个任务启用不了（任务 XML `<Enabled>false</Enabled>`、文件 ACL 对 Administrators 只读） |
| 遥测降级 | `AllowTelemetry=0` 只对企业版 / 教育版 / Server 生效；家庭版 / 专业版忽略它，按 SKU 门控写 `1`（消费版写 0 是空操作） |
| 累积更新 | 更新**删除** `tune` 写入的值（含整键、整子树），判据是"值存在"而非"值等于期望"；打完更新重跑 `verify-env.ps1` |
| computer use（Win10 19045） | 不装：Cua Driver 在该 build 崩溃 `0xC0000005` / 枚举挂死 / 二进制未签名（[#2298](https://github.com/trycua/cua/issues/2298)、[#2113](https://github.com/trycua/cua/issues/2113)、[#2066](https://github.com/trycua/cua/issues/2066)）；上游 `WINDOWS_TEST.md` 开头即 `BLOCKED — no Windows GUI test environment available`。替代：PowerShell 脚本 + Playwright + 截图交给 AI 读 |
| SSH 与凭据 | `github.com:22` 阻断时走 `ssh.github.com:443`，主机密钥按 [GitHub 官方指纹](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) 校验；公钥在 https://github.com/settings/keys 添加；密钥无 passphrase 时私钥被拷贝即可用（判据：`ssh-keygen -y -f <key>` 直接输出公钥、不提示口令） |

> 本文件只定"什么算配好了"与怎么验：每条调优的正确值与依据见 `03-system-tweaks.md`，
> 工具链与 13 项软件的安装细节见 `04-dev-and-apps.md`，做 / 不做的取舍见 `02-decisions.md`。
