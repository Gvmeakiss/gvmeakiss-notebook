# Windows 陷阱参考

> 报错信息与真实原因不一致的常见情形。四列固定：**症状**（看到的现象）/ **根因**（实际发生的事）/ **判据**（怎么确认）/ **正确做法**。
> 命令按原样记录，注册表路径保持反斜杠形式；只保留可复用的症状、根因、判据与做法。

---

## 1. 工具「缺失」与编码

| 症状 | 根因 | 判据（怎么确认） | 正确做法 |
|---|---|---|---|
| `python` 提示去 Microsoft Store 安装，装了真 Python 仍如此 | `%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe` 是 0 字节重解析点（Store 存根），解析优先级高于 PATH 中的真实 Python | `Get-Item "$env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe"` 的 `Length` 为 0；`where.exe python` 首条命中 `WindowsApps` | 删除或移走存根，在真实 Python 目录补建 `python.exe` / `python3.exe`，使用户 PATH 中真实目录排在 `WindowsApps` 之前 |
| 所有 `scoop` 命令报 `not recognized` | `~\scoop\shims` 不在 PATH | `where.exe scoop` 无输出；`Test-Path "$env:USERPROFILE\scoop\shims"` 为 True | 把 `~\scoop\shims` 加入用户 PATH，广播环境变量变更并开新终端 |
| 重装工具无效，时好时坏 | GUI 父进程的环境变量是启动时快照，早于配置变更 | 同一命令在新终端正常，在脚本或 GUI 子进程里失败 | 脚本从注册表重建 PATH（见 §4），不依赖继承环境 |
| 工具已安装但脚本找不到 | 包管理器装进 `persist\` 等未加入 PATH 的目录 | 按目录能找到 exe，`where.exe` 找不到 | 按安装路径回读 exe，把该目录加入 PATH；不要只查命令名 |
| `python` 可用而 `python3` 不可用（或反之） | scoop 的 python 清单可能只建 `python3` 而不建 `python` | 分别 `where.exe python` 与 `where.exe python3`，缺一个 | 在真实 Python 目录补建缺失名字的副本，排在 `WindowsApps` 之前 |
| 中文 Windows 上 `UnicodeDecodeError: 'gbk' codec can't decode byte 0x9f in position 341` | 区域编码为 GBK，Python 默认按平台编码读文件 | 同一文件在 Mac/Linux 正常、在中文 Windows 失败；错误码为 `gbk` | `path.read_text(encoding='utf-8')`；`PYTHONUTF8=1` 只作辅助，不能当唯一修法 |
| Rust GNU 目标构建报 `error calling dlltool 'dlltool.exe': program not found` | 链接 proc-macro 时调用 `dlltool`，MinGW binutils 不在 PATH | `where.exe dlltool` 无输出；报错出现在依赖构建深处而非本项目 | 安装 MinGW binutils 并把其 `bin` 目录加入 PATH |
| `Test-Path` 返回 True、脚本判定已安装，调用时仍报 not recognized 或无法执行 | `Test-Path` 把 `*` 当通配符；路径存在不等于能执行 | 取不到版本号，或真实编译失败 | 验收只认版本号与真实编译：`python --version` / `go version` / `gcc -dumpfullversion -dumpversion` |

```python
path.read_text()                    # 错误：依赖平台默认编码
path.read_text(encoding='utf-8')    # 正确：跨平台一致
```

> 纪律：任何「缺失」结论，先排除 PATH 与存根，再谈安装。

---

## 2. 认证与凭据

| 症状 | 根因 | 判据（怎么确认） | 正确做法 |
|---|---|---|---|
| 已配置凭据助手，`git` 仍反复要求输入用户名/密码 | `git-credential-manager configure` 往系统级 `etc/gitconfig` 写入空值 `credential.helper =`，往全局追加转义错误的绝对路径；空值让 git 忽略真正的 helper，回退到终端询问 | `git config --system --get-all credential.helper` 输出空值；`git config --show-origin --get-all credential.helper` 可见来源为 `etc/gitconfig` | 清掉系统级与全局空值，只留一条正确的 `manager` |
| 浏览器显示的是另一个 GitHub 账号，授权直接通过，拿不到目标账号的令牌 | HTTPS + Git Credential Manager 打开浏览器 OAuth 页；浏览器已登录的账号被 GitHub 复用批准请求 | 追踪日志出现 `OpenBrowserInternal: Opening browser using shell-execute:` 与 `username=<另一个账号>`；`gh auth status` 账号不符 | `gh auth login` 设备码方式（显式输入 8 位码，不复用浏览器登录态），随后 `gh auth setup-git`；或改用 SSH |
| `github.com:22` 上 SSH 握手被切断：`kex_exchange_identification: Connection closed by remote host` | 端口 22 被网络封锁；TCP 可连通，但握手被中途切断 | `ssh -T git@github.com` 可复现；换 443 端口成功 | 用 GitHub 官方 `ssh.github.com:443`，并用官方指纹校验主机密钥 |
| `ssh-keygen` 生成的密钥本地无法签名，GitHub 端却已接受 | `-N '""'` 让外层单引号内的两个引号成为口令字面量 | 调试输出 `Server accepts key:` 后紧跟 `we did not send a packet, disable method`；`ssh-keygen -y -f <key>` 提示输入口令 | 用 `-N ""` 重建；验证 `ssh-keygen -y -f <key>` 直接输出公钥、不提示口令 |

```powershell
git config --system --unset-all credential.helper
git config --global --unset-all credential.helper
git config --global credential.helper manager   # 只留一条正确的
```

> `credential.https://github.com.helper=` 这种带 URL 的空值不清空链（`gh auth setup-git` 会写它，属正常）；只有无 URL 的 `credential.helper=` 空值才有清空语义。

```powershell
ssh-keygen -t ed25519 -f <path> -N '""'   # 错误：外层单引号让字面量两个引号成为口令
ssh-keygen -t ed25519 -f <path> -N ""     # 正确
ssh-keygen -y -f <key>                    # 应直接输出公钥、不提示口令
```

| 算法 | 官方指纹 |
|---|---|
| ED25519 | `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` |
| ECDSA | `SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM` |
| RSA | `SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s` |

来源：[GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)

---

## 3. 默认程序与文件关联

| 症状 | 根因 | 判据（怎么确认） | 正确做法 |
|---|---|---|---|
| 修改默认程序返回 `Requested registry access is not allowed.` | `UserChoice` 键带显式 `Deny SetValue` ACE 与 `Hash`（ProgId + SID + 时间戳）；`Deny` 压过 `Allow FullControl`，管理员也改不了 | `Get-Acl "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<扩展名>\UserChoice"` 可见当前用户 `Deny SetValue` 与同时存在的 `Allow FullControl`；键值含 `ProgId` / `Hash`；写入被拒 | 不脚本化改默认程序：`reg export` 备份关联分支、注册 ProgID 让程序出现在「打开方式」列表、对其余扩展名提示手动点一次 |
| 官方 COM API 的 `SetAppAsDefault` 返回 `0x80070002`，默认程序未变 | Win10+ 上 `IApplicationAssociationRegistration`（CLSID `591209c7-767b-42b2-9fba-44ee4615f2c7`）的写入接口已被策略禁止；错误码 `ERROR_FILE_NOT_FOUND` 与真实原因无关 | `QueryAppIsDefault` 正常返回；`SetAppAsDefault` / `SetAppAsDefaultAll` 返回 `0x80070002`；回读 `UserChoice` 未变 | 放弃该 API；只做注册与候选，默认程序手动设置 |
| ProgID 已注册，「设置 → 默认应用 → 按文件类型选择」里仍看不到程序 | 只写了 `HKCU\Software\Classes\Applications\<exe>`，漏了 `HKCU\Software\<Vendor>\Capabilities` 与 `HKCU\Software\RegisteredApplications` | 前者决定右键「打开方式」列表；后者决定设置页可见性，两处分别查询 | 两条路径都写；改完调用 `SHChangeNotify` 通知资源管理器刷新 |
| 注册表关联写对，双击文件仍没打开 | 关联注册正确不等于进程能启动（路径、参数、单实例） | 启动前后进程 diff：没有新进程即未真正打开 | 先清掉同程序已在运行的实例，再启动测试并观察新进程 |
| 卸载便携程序后双击文件报错，「打开方式」里有幽灵项 | 便携版删文件夹即卸载，注册表关联不跟着消失：`UserChoice` 指向已删程序、ProgID 残留、`RegisteredApplications` / `Capabilities` 指向已删程序 | 对每个扩展名取默认 ProgID，再查其 `shell\open\command` 指向的 exe 是否存在 | `UserChoice` 失效必须修，其余残留可清理；删程序后主动跑关联检查，把 ProgID 重定向到幸存程序，不要删键（Windows 会重建并可能指向第三个程序） |
| 「应用和功能」里看不到已装的便携软件 | 便携软件不写卸载注册表项，不进系统应用列表 | 系统应用列表为空，但安装目录与 exe 存在 | 目录扫描 + 多路并查（便携目录、`Program Files`、`WinGet\Packages`），按清单相对路径回读 exe |

```powershell
Add-Type -Namespace W32 -Name Notify -MemberDefinition `
  '[DllImport("shell32.dll", CharSet=CharSet.Auto)] public static extern void SHChangeNotify(int a, uint b, IntPtr c, IntPtr d);'
[W32.Notify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
```

```powershell
$before = @{}; Get-Process | ForEach-Object { $before[$_.Id] = $_.Name }
Start-Process <被关联的文件或 exe>
Start-Sleep 8
$new = Get-Process | Where-Object { -not $before.ContainsKey($_.Id) }
$new | Select-Object -ExpandProperty Name -Unique      # 有输出才算真的打开成功
$new | Stop-Process -Force                             # 测试后清理
```

```powershell
# 对每个关心的扩展名，看它的默认 ProgID 指向的 exe 是否还存在
foreach ($ext in '.md','.png','.mp4') {
    $uc  = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $cls = (Get-ItemProperty "HKCU:\Software\Classes\$ext" -ErrorAction SilentlyContinue).'(default)'
    $progId = if ($uc) { $uc } else { $cls }
    $cmd = (Get-ItemProperty "HKCU:\Software\Classes\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    "{0,-8} {1,-30} {2}" -f $ext, $progId, $cmd
}
```

---

## 4. PowerShell 脚本

| 症状 | 根因 | 判据（怎么确认） | 正确做法 |
|---|---|---|---|
| 函数一行未执行，也没有任何报错 | `$PSCmdlet` 只在 `[CmdletBinding()]` 函数内存在；普通函数里为 `$null`，`.ShouldProcess()` 抛错，在 `$ErrorActionPreference='Continue'` 下静默中断 | 函数内 `$PSCmdlet` 为 `$null`；函数未声明 `[CmdletBinding()]` | 脚本级捕获一次 `$Cmdlet = $PSCmdlet`，之后统一 `$Cmdlet.ShouldProcess(...)` |
| 函数内的提示信息全部消失 | `[void](SomeFunction)` 丢弃该函数全部输出，包括提示信息 | 调用点带 `[void]`，函数内有 `Write-Output` | 不要用 `[void]` 包整个函数；提示走 `Write-Host` / `Write-Information`，或返回对象后统一输出 |
| 哈希表初始化报解析错误 | 哈希表裸键名不能含运算符字符，`g++` 未加引号 | 键名含 `+` 等字符且未加引号 | `$h = @{ 'g++' = @('--version') }` |
| 已装工具在脚本内报缺失 | 进程环境变量是启动时快照，GUI 父进程的 PATH 早于配置 | 同一命令在新终端正常，在脚本或 GUI 子进程失败 | 脚本从注册表重建 PATH |
| `-File` 调用 `-Only A,B` 只收到一个元素 | `-File` 模式不把 `A,B` 拆成数组（`-Command` 会拆） | 参数计数为 1，脚本报「无匹配项」 | 脚本内 `-split ','`，或改用 `&` 在进程内调用传数组 |
| 子脚本失败，调用方仍判成功 | `$LASTEXITCODE` 不会被进程内调用更新，保留上一个子进程的值 | 同一会话 `& .\child.ps1` 后该变量不变 | 真起子进程取退出码，或解析子脚本输出的判定表 |
| `-WhatIf` 预演仍然改了系统 | `-WhatIf` 是进程级偏好，不跨进程传递 | 子进程命令行里没有 `-WhatIf`；预演后系统已变 | 每个跨进程调用显式转发；只对声明 `SupportsShouldProcess` 的子脚本转发 |
| 无 BOM 的中文 `.ps1` 在 5.1 下解析失败、PS7 正常 | 5.1 按 ANSI 解码无 BOM 文件，PS7 按 UTF-8 解码 | `check-script-hygiene.ps1` 双宿主解析报错；5.1 报 `The string is missing the terminator: '` 一类错误 | 脚本 ASCII-only，或存成 UTF-8 BOM；改完跑 `check-script-hygiene.ps1` |
| `Get-AppxPackage` 在 PS7 报 `0x80131539`，加 `-ErrorAction SilentlyContinue` 后静默返回空 | Appx 模块是 5.1 专有（依赖 .NET Framework 的 WinRT 互操作），在 PowerShell 7 里整个模块加载失败 | PS7 复现，`powershell.exe` 正常 | 查 UWP 一律用 `powershell.exe`（5.1） |
| `foreach ($kv in $hashtable)` 只循环一次，`$kv.Key` 为 `null` | 哈希表本身不是条目集合，`[ordered]@{}` 同样 | 循环体只执行一次；后续报「无法将自变量绑定到参数 Name」 | `$h.GetEnumerator()`；管道方式会正常枚举 |

```powershell
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path','Machine'),
    [Environment]::GetEnvironmentVariable('Path','User')
) | Where-Object { $_ }) -join ';'
```

---

## 5. 注册表、服务与计划任务

| 症状 | 根因 | 判据（怎么确认） | 正确做法 |
|---|---|---|---|
| 遍历 `HKCU\Software\Classes` 逐键读 command 耗时数分钟 | PowerShell 每键一次 `Get-ItemProperty`，853 个子键约 281 秒 | 计时对比；同样的信息用 `reg query` 是秒级 | `reg query 'HKCU\Software\Classes' /s /ve` 全量 dump 后内存过滤 |
| `reg query /f 'shell\open\command' /k` 永远返回 0 条 | `/f` 不能跨反斜杠匹配键名，只匹配单层键名 | 逐层查同一路径有结果，`/f` 无结果 | 逐层查，或 `/s` 全量输出后自行过滤 |
| 向同一键写多个值，最后只剩一个，却报 applied N | `New-Item <键> -Force` 对已存在键是重建，删除键内全部值 | 汇总计数与实际存活值不符；逐值回读可见缺失 | 仅当键不存在时才创建；验证按键逐值回读，不看汇总计数 |
| `reg import` 返回 exit 1，已写的保留，后面的节全部跳过 | `reg import` 是部分写入：一个键被拒会跳过其后所有节 | 回读报后面 N 个值缺失；真凶是中间一个被锁的键；exit 1 | 可写性未知的键单独成批，或改用官方策略键 |
| ACL 显示 `FullControl`、属主是本人、进程已提权，写入仍 `Access is denied.` | 受内核级保护的键，不是 ACL 问题 | `reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f` 返回 `ERROR: Access is denied.`，同批其它键成功 | 不夺所有权、不改 ACL；改用官方策略键 |
| MMCSS 的 `Start` / `Type` / `ErrorControl` 全对，`sc start MMCSS` 仍返回 1341 | 引导期内核驱动在运行中途起不来；同一次开机内反复 `sc start` 无效 | `sc.exe qc MMCSS` 配置正确、驱动文件与签名有效；事件日志为 7000，`sc start` 返回 1341 | 重启后再验；需要时 `sc.exe config MMCSS start= auto` 加 `sc.exe start MMCSS`，判据是 `sc query` 显示 `RUNNING` |
| 计划任务报 `0x1`，任务历史却全显示成功 | 任务历史记录的是调度器动作（已启动、操作完成），不记录子进程退出码；`TaskScheduler/Operational` 日志默认禁用 | `Get-ScheduledTaskInfo` 的 `LastTaskResult=0x1`；历史停在「任务成功完成」 | 先 `wevtutil set-log "Microsoft-Windows-TaskScheduler/Operational" /e:true`，再按 `LastTaskResult` 判定 |
| 任务参数里的 `> log 2>&1` 不生成日志，任务仍报成功 | 参数栏不通过 Shell 执行，重定向无效；任务工作目录是 `C:\Windows\System32` | 日志文件不存在，任务结果成功 | 日志由脚本自己写（`Add-Content` / `[IO.File]::WriteAllText`）；所有路径写全 |
| 非提权运行 `bcdedit` 无输出也不报错 | 无权限时静默返回空，不提示「拒绝访问」 | 提权后同一命令有输出，非提权时为空 | 提权执行后再判断；不要把空输出读成「设置被清空」 |
| `-Verb RunAs` 配 `-RedirectStandardOutput` 直接报参数集错误，UAC 不弹 | `Start-Process` 的这两个参数不能同时使用 | 报「无法使用指定的命名参数解析参数集」 | 提权脚本日志用 `Start-Transcript`，不用输出重定向 |

```powershell
# 慢：853 个键逐一 Get-ItemProperty，约 281 秒
foreach ($s in Get-ChildItem 'HKCU:\Software\Classes') {
    try { $c = (Get-ItemProperty "$($s.PSPath)\shell\open\command" -ErrorAction Stop).'(default)' } catch { continue }
}

# 快：原生 exe，同样的信息
reg query 'HKCU\Software\Classes' /s /ve
```

```powershell
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f
#   -> ERROR: Access is denied.

reg add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v ConnectedSearchUseWeb /t REG_DWORD /d 0 /f
```
