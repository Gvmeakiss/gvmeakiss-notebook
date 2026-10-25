# 开发环境与软件

这一段的目标是一个可复现的终态：**新开一个终端，每条命令都能跑出版本号，13 项软件每一项都能在盘上回读到声明的路径**。
要装什么由 [`02-decisions.md`](./02-decisions.md) 的判定决定，条目一律以清单为准；装完怎么证明，由这一段负责。
全部动作由 `skills/win-ai-gaming-setup` 的 `check → dev → apps → link → verify` 五个阶段完成；`drivers` 与 `tune` 属系统层，见 [`03-system-tweaks.md`](./03-system-tweaks.md)。

命令在仓库根执行，下文 `setup.ps1` 指 [`skills/win-ai-gaming-setup/scripts/setup.ps1`](../skills/win-ai-gaming-setup/scripts/setup.ps1)。

## 阶段与命令

| 阶段 | 命令 | 产物 | 成功判据 |
|---|---|---|---|
| `check`（前置） | `pwsh -File skills/win-ai-gaming-setup/scripts/setup.ps1 -Phase check` | `scoop`、`git`、`7-Zip`、`git core.longpaths=true` | 结果表 `check PASS`；`git config --global core.longpaths` 回读 `true` |
| `dev` | `setup.ps1 -Phase dev` | `python` `nodejs` `go` `rust` `dotnet` `mingw`/`cmake` `uv`、6 个镜像 + `HF_ENDPOINT`、VS Code / Windows Terminal、`fix-env.ps1` 修复 | [`setup-langs.ps1`](../skills/win-ai-gaming-setup/scripts/setup-langs.ps1) 汇总行 `all requested packages installed and mirrors configured`；结果表 `dev PASS` |
| `apps` | `setup.ps1 -Phase apps` | `%USERPROFILE%\Apps\<名称>` 下 5 个便携软件 + 8 个 winget 条目 | [`install-portable.ps1`](../skills/win-ai-gaming-setup/scripts/install-portable.ps1) 汇总行 `all selected apps installed and verified (N/M)`，M = 清单条目数 = 13 |
| `link` | `setup.ps1 -Phase link -RegisterAssociations` | HKCU 关联注册（`Applications` + `Capabilities`/`RegisteredApplications`）、注册表备份、孤儿扫描 | 逐类型"仍需手点"清单 + 孤儿扫描无残留。**结果表 `link` 恒为 PASS，不能当判据** |
| `verify` | `setup.ps1 -Phase verify` | `verify-env.ps1` + `check-software.ps1` + `diagnose-ime.ps1` 的汇总 | `total: N checks, 0 failed`、`declared apps 13/13 present`、退出码 0 |
| 预设 | `setup.ps1 -Profile dev` | 以上五段一次跑完 | 结果表 5 行全 `PASS`；退出码 0 |

- 退出码 = FAIL 的阶段数（脚本末行 `exit $fail`），**只有 0 表示通过**；子脚本的退出码各有含义，见上表各行的判据。
- `LongPathsEnabled=1` 与开发者模式需要管理员；非管理员只落 `git core.longpaths=true`，这两项只 `WARN`，不影响 `check` 的结果。
- 编辑器（VS Code / Windows Terminal）安装失败只 `WARN`，不进 `dev` 结果；用 `Get-Command code` 单独回读。
- `-WhatIf` 只转发给声明了 `SupportsShouldProcess` 的子脚本；判据是输出里逐条 `WOULD` / `would ...`，且没有真实写入。

## 语言工具链

| 生态 | 包管理器 | 镜像源 | 验证命令 |
|---|---|---|---|
| Python | scoop `python` + `pip` | `pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple`（同时设 `global.trusted-host`） | `python --version`；`python -m pip config get global.index-url` |
| Node.js | scoop `nodejs` + `npm` | `npm config set registry https://registry.npmmirror.com` | `node --version`；`npm config get registry` |
| Go | scoop `go` | `go env -w GOPROXY=https://goproxy.cn,direct`、`go env -w GOSUMDB=sum.golang.google.cn` | `go version`；`go env GOPROXY` |
| Rust | rustup（`--default-host x86_64-pc-windows-gnu`）+ `cargo` | `RUSTUP_DIST_SERVER=https://rsproxy.cn`、`RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup`；`$CARGO_HOME\config.toml` → `sparse+https://rsproxy.cn/index/` | `rustc -vV`（host 必须是 `x86_64-pc-windows-gnu`）；`cargo --version` |
| .NET | scoop `dotnet-sdk` | `%APPDATA%\NuGet\NuGet.Config`：`api.nuget.org/v3/index.json` 主 + `repo.huaweicloud.com/repository/nuget/v3/index.json` 备 | `dotnet --version`；`dotnet nuget list source` |
| C / C++ | scoop `mingw` + `cmake` | 无（编译器不走包管理器） | `g++ --version`；`cmake --version` |
| uv | scoop `uv` | 未配置（脚本只负责安装） | `uv --version` |
| Java | scoop `temurin21-jdk`（`java` bucket） | 无 | `javac -version` |

- 默认集是 `-Languages`（`python,nodejs,go,cmake,dotnet-sdk,mingw,uv`）加 Rust（由 `setup-langs.ps1` 的默认集带入，走 rustup 而不是 scoop 的 MSI）；**Java 不在默认集**，要 `-Languages java`，或单独跑 `pwsh -File skills/win-ai-gaming-setup/scripts/setup-langs.ps1 -Packages java`。
- 版本号只证明"能启动"。`verify-env.ps1` 对每种生态另做一次真实编译并运行（`run` / `build` 行），那一行才是判据。
- pip / npm / go / cargo 的镜像写入都以"该工具已在 PATH 上"为前置条件。工具没装上，对应镜像**不会被写**，且不会为此单独报错 —— 只在 `dev` 阶段的 `mirror state` 回读里显示 `NOT configured`。`NuGet.Config` 不受此条件约束，文件不存在就写。
- `NuGet.Config` 与 `config.toml` 已存在时脚本不覆盖（保留人工调过的值），所以"镜像没变"不等于"没写"。

## 便携软件

13 条，全部来自 [`apps.json`](../skills/win-ai-gaming-setup/apps.json)：8 条 `source: winget`、5 条便携归档。

| 名称 | 来源 | 校验 | 关联类型 |
|---|---|---|---|
| 7-Zip | winget `7zip.7zip` | 回读 `%ProgramFiles%\7-Zip\7z.exe` | — |
| WinRAR | winget `RARLab.WinRAR` | 回读 `%ProgramFiles%\WinRAR\WinRAR.exe` | — |
| JPEGView | 便携 zip · `sylikc/jpegview` v1.3.46 | sha256 `ba71d598…` + 回读 `JPEGView64\JPEGView.exe` | 图片 8 类：`.png .jpg .jpeg .gif .bmp .webp .tif .tiff` |
| MPC-BE | 便携 7z · `Aleksoid1978/MPC-BE` 1.9.1 | sha256 `d9ef12c0…` + 回读 `mpc-be64.exe` | 音视频 9 类：`.mp4 .mkv .avi .mov .webm .mp3 .flac .wav .m4a` |
| Notepad++ | 便携 zip · v8.9.8.1 | sha256 `beddf554…` + 回读 `notepad++.exe` | 文本 9 类：`.txt .md .markdown .ini .log .json .xml .yml .yaml` |
| TrafficMonitor | 便携 zip · V1.86 | sha256 `948ddc12…` + 回读 `TrafficMonitor.exe` | — |
| rclone | 便携 zip · v1.75.1 | sha256 `200eb602…` + 回读 `rclone.exe` | — |
| VC++ 2010 x86 | winget `Microsoft.VCRedist.2010.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr100.dll` | — |
| VC++ 2010 x64 | winget `Microsoft.VCRedist.2010.x64` | 回读 `%SystemRoot%\System32\msvcr100.dll` | — |
| VC++ 2012 x86 | winget `Microsoft.VCRedist.2012.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr110.dll` | — |
| VC++ 2012 x64 | winget `Microsoft.VCRedist.2012.x64` | 回读 `%SystemRoot%\System32\msvcr110.dll` | — |
| VC++ 2013 x86 | winget `Microsoft.VCRedist.2013.x86` | 回读 `%SystemRoot%\SysWOW64\msvcr120.dll` | — |
| VC++ 2013 x64 | winget `Microsoft.VCRedist.2013.x64` | 回读 `%SystemRoot%\System32\msvcr120.dll` | — |

- 13 条的构成：2 个压缩工具 + 5 个便携软件 + 6 个 VC++ 运行库，与 [`01-baseline.md`](./01-baseline.md) 的清单口径一致。
- `sha256` 取前 8 位示意，完整值在 `apps.json`；比较时按大写逐字相等。
- 关联类型 ≠ 默认程序：`assoc` 只让程序出现在"打开方式"列表。默认程序由 `UserChoice` 保护（显式 `Deny SetValue` + `Hash`），脚本改不了，必须每类手点一次。
- Notepad++ 与 TrafficMonitor 带 `altPaths`（`%ProgramFiles%\Notepad++`、WinGet Packages 下的 TrafficMonitor）：回读接受这些位置，但**不阻止**便携副本的安装，两处都在都算 OK。

## 安装回读

"装好"只有一种证明方式：**回到磁盘上把声明的路径读出来**。

1. **winget 条目**只认 `verifyPath` 是否存在（`%VAR%` 会展开）。`winget exit code: 0` 会打印出来，但不作证据；装完立刻回读，失败即 `still missing after install`。
2. **便携条目**先过哈希闸门：不符打 `SHA256 MISMATCH - refusing to install` 并删除下载，**不会解压**。归档哈希只证明"下载完整"，不证明"布局符合清单"。
3. 解压后先折叠唯一的顶层目录，再回读 `exe`（**相对**安装根，不能取文件名）。回读不到是 `FAIL`，不是"跳过快捷方式"。JPEGView 的归档有 `JPEGView32` / `JPEGView32-WinXP` / `JPEGView64` 三个顶层目录，单层折叠不适用，`exe` 必须写 `JPEGView64\JPEGView.exe`。
4. **汇总计数**：成功打 `all selected apps installed and verified (N/M)`；有失败打 `failed (K): <名称>` 和 `verified (N/M): <名称>` 并以退出码 1 结束。"没有失败"与"每个都在盘上"是两件事，只有后者进 N。
5. **独立回读**：`check-software.ps1` 的 `Declared apps (manifest)` 段逐条打 `OK` / `MISS`，带 `[portable]` / `[vendor]` / `[alt]` 来源标记，汇总行 `declared apps 13/13 present`。该脚本**不设退出码**（恒 0），所以 `verify` 阶段的 PASS 不能替代这一行。

```powershell
$root = Join-Path $env:USERPROFILE 'Apps'
$man  = Get-Content '.\skills\win-ai-gaming-setup\apps.json' -Raw -Encoding UTF8 | ConvertFrom-Json

# 逐条回读（与安装器同一判据：winget 看 verifyPath，便携看 exe 相对路径）
# 本循环不含 altPaths：Notepad++ / TrafficMonitor 常由 winget 装在别处，最终判据看下面的 check-software
foreach ($a in $man.apps) {
    if ($a.verifyPath) { $p = [Environment]::ExpandEnvironmentVariables($a.verifyPath) }
    else { $p = Join-Path (Join-Path $root $a.name) $a.exe }
    '{0,-18} {1}' -f $a.name, $(if (Test-Path -LiteralPath $p) { "OK   $p" } else { 'MISS' })
}

# 缓存归档与清单逐条对哈希
$man.apps | Where-Object { $_.sha256 } | ForEach-Object {
    $f = Join-Path (Join-Path $root '.installers') (Split-Path ([uri]$_.url).AbsolutePath -Leaf)
    if (Test-Path -LiteralPath $f) { '{0,-14} {1}' -f $_.name, $(if ((Get-FileHash $f -Algorithm SHA256).Hash -eq $_.sha256.ToUpperInvariant()) { 'OK' } else { 'MISMATCH' }) }
}

# 含 altPaths 与版本号的完整回读，判据是汇总行 declared apps 13/13 present
pwsh -File skills/win-ai-gaming-setup/scripts/check-software.ps1 -PortableRoot "$env:USERPROFILE\Apps"
```

版本号取自 exe 的文件元数据（`(Get-Item <exe>).VersionInfo.FileVersion`），不是清单声明；版本与清单吻合才说明跑的是这一版。

## 环境变量与 PATH

全部写在用户作用域，**只对新终端生效**（脚本改注册表，不改已运行的进程）。脚本自身启动时会从注册表重建 `$env:PATH`，因此：**脚本能查到而你的终端查不到 ⇒ 终端陈旧，不是没装**。

| 项 | 期望值 |
|---|---|
| 用户 PATH | 含 `%USERPROFILE%\.cargo\bin`（设了 `CARGO_HOME` 则是 `%CARGO_HOME%\bin`） |
| 用户 PATH | 含 `<Destination>\MPC-BE`、`<Destination>\Notepad++`、`<Destination>\rclone`（清单里 `addToPath: "."`） |
| `RUSTUP_DIST_SERVER` | `https://rsproxy.cn` |
| `RUSTUP_UPDATE_ROOT` | `https://rsproxy.cn/rustup` |
| `HF_ENDPOINT` | `https://hf-mirror.com` |

```powershell
# 用户 PATH：这四条必须命中（CARGO_HOME 有值时第一条换成 %CARGO_HOME%\bin）
$userPath = ([Environment]::GetEnvironmentVariable('Path','User')) -split ';'
@(
  (Join-Path $env:USERPROFILE '.cargo\bin'),
  (Join-Path $env:USERPROFILE 'Apps\MPC-BE'),
  (Join-Path $env:USERPROFILE 'Apps\Notepad++'),
  (Join-Path $env:USERPROFILE 'Apps\rclone')
) | ForEach-Object { '{0,-6} {1}' -f $(if ($userPath -contains $_) { 'OK' } else { 'MISS' }), $_ }

# 用户级变量
foreach ($n in 'RUSTUP_DIST_SERVER','RUSTUP_UPDATE_ROOT','HF_ENDPOINT') {
    '{0,-20} {1}' -f $n, [Environment]::GetEnvironmentVariable($n,'User')
}

# 新终端里的终态判据：版本号，不是命令是否存在
python --version; node --version; go version; rustc -vV; dotnet --version; g++ --version; cmake --version
```

- 路径 `MISS` 时按安装器相同的方式补一条：`[Environment]::SetEnvironmentVariable('Path', "$dir;$cur", 'User')`（`$cur` 取自 `GetEnvironmentVariable('Path','User')`），然后开新终端。已存在的安装目录重跑 `-Phase apps` **不会**补 PATH —— 那条分支命中 `Test-Path $target` 就直接 `continue` 了。
- 镜像的落点是**配置文件**，不是环境变量。判断 pip / npm / go 的镜像要读各自的配置（`pip config get` / `npm config get` / `go env`），不要读 `$env:PIP_INDEX_URL`。
- `PYTHONUTF8=1` 只是缓解手段：中文 Windows 上 Python 默认按 GBK 读文件，代码里必须显式 `encoding='utf-8'`，CI 和别人的机器不会替你设这个变量。

## 常见失败与判据

| 症状 | 判据 | 处理 |
|---|---|---|
| 新终端里 `node` / `cargo` 仍 `not recognized` | 脚本（自建 PATH）能查到、当前终端查不到 ⇒ 只是进程环境陈旧 | 开新终端，不要重装 |
| `python` 弹出应用商店 | `Get-Command python` 指向 `WindowsApps` 下的 0 字节重解析点 | `fix-env.ps1` 重建 shim（`dev` 阶段已调用），`-SkipAliasRemoval` 可跳过 |
| `setup-langs.ps1` 打了一串 ok 但整体失败 | 汇总行 `failures (N)` 非空、退出码 1 | 按列出的包重跑（幂等，已装跳过），别把大段 ok 当成功 |
| 所有 `.zip` 条目解压失败（`extraction failed (exit 2)`） | 手上只有 `7zr.exe` —— 它是精简版，**没有 ZIP codec** | 先让 `7-Zip` 条目落地；`.zip` 走内置解压，`7zr` 只用于 `.7z` |
| `SHA256 MISMATCH - refusing to install` | 下载文件哈希与清单不等（镜像改包、版本被替换） | 删 `Apps\.installers\<文件名>` 重下；仍不等就核对 `url` 与版本 |
| `extracted, but <exe> is not there` / `folder exists but <exe> is missing` | 目录在，清单声明的相对 `exe` 不在 | 删该目录重跑，或修清单的 `exe`（JPEGView 必须是 `JPEGView64\JPEGView.exe`） |
| `winget exit code: 0` 但 `still missing after install` | `verifyPath` 不存在 | 从厂商站手装后重跑 `-Phase apps` |
| 镜像"配过了"但下载仍走官方源 | `NuGet.Config` / `config.toml` 已存在则不覆盖；cargo 认 `$env:CARGO_HOME` 而非固定 `~\.cargo` | 按实际路径核对文件内容，必要时手工改 |
| 双击文件仍用旧程序 | `UserChoice` 带 `Deny SetValue` + `Hash`，脚本无法改 | 右键 → 打开方式 → 选择程序 → 勾"始终使用"，每类一次 |
