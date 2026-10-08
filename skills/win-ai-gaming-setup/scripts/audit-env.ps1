<#
.SYNOPSIS
  Read-only audit of a Windows development environment.

.DESCRIPTION
  Collects facts about OS, toolchains, PATH, environment variables, package-manager
  caches and mirror reachability. Performs NO modifications.

  Design rule: report facts, never guess. Every check prints the raw command output
  so the operator can verify the conclusion instead of trusting a summary.

.PARAMETER Json
  Emit a machine-readable JSON report instead of the human-readable form.

.EXAMPLE
  pwsh -File audit-env.ps1
  pwsh -File audit-env.ps1 -Json | Out-File audit.json

.NOTES
  Requires PowerShell 7+ (pwsh) for full fidelity; degrades gracefully on 5.1.
  ASCII-only on purpose: keeps the script byte-identical under any code page.
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [string[]]$Languages = @('python','node','go','rust','java','dotnet','gcc','git'),
    [string[]]$PackageManagers = @('scoop','winget','choco','npm','pip','cargo','go','dotnet','nuget')
)

$ErrorActionPreference = 'Continue'
$report = [ordered]@{}

# A GUI/agent parent process may predate the current PATH configuration, so its inherited
# environment can be stale and make installed tools look missing. Rebuild the process PATH
# from the registry (Machine + User) before probing anything.
$machinePathValue = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPathValue = [Environment]::GetEnvironmentVariable('Path', 'User')
$staleProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
$env:PATH = (@($machinePathValue, $userPathValue) | Where-Object { $_ }) -join ';'
$report.ProcessPathWasStale = ($staleProcessPath -ne $env:PATH)

function Section { param([string]$Title) if (-not $Json) { Write-Output "`n===== $Title =====" } }
function Row { param([string]$Label, $Value) if (-not $Json) { '{0,-22} {1}' -f $Label, $Value } }

# ----------------------------------------------------------------- OS / hardware
Section 'OS and hardware'
$os = $null
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}
$build = if ($os) { [int]$os.BuildNumber } else { 0 }
$osInfo = [ordered]@{
    Caption = if ($os) { $os.Caption } else { $null }
    Version = if ($os) { $os.Version } else { $null }
    Build   = $build
    # Windows 11 starts at build 22000. Many GUI-automation / UIA toolkits only
    # support Windows 11; knowing this up front prevents installing a dead end.
    IsWindows11OrLater = ($build -ge 22000)
    Arch    = if ($os) { $os.OSArchitecture } else { $null }
}
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $osInfo.Cpu = $cpu.Name
    $osInfo.CpuCores = $cpu.NumberOfCores
    $osInfo.CpuThreads = $cpu.NumberOfLogicalProcessors
} catch {}
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $osInfo.RamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
} catch {}
$report.OS = $osInfo
foreach ($k in $osInfo.Keys) { Row $k $osInfo[$k] }

# ----------------------------------------------------------------- privilege
Section 'Privilege and shell'
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}
$priv = [ordered]@{
    User        = "$env:USERDOMAIN\$env:USERNAME"
    IsAdmin     = $isAdmin
    PSVersion   = $PSVersionTable.PSVersion.ToString()
    LanguageMode = "$($ExecutionContext.SessionState.LanguageMode)"
}
try { $priv.ExecutionPolicy = (Get-ExecutionPolicy -Scope CurrentUser).ToString() } catch {}
$report.Privilege = $priv
foreach ($k in $priv.Keys) { Row $k $priv[$k] }

# ----------------------------------------------------------------- toolchains
Section 'Toolchains'
$toolchains = [ordered]@{}
# (exe, version args, extra env values to print)
$probes = @{
    python = @('--version')
    pip    = @('--version')
    node   = @('--version')
    npm    = @('--version')
    go     = @('version')
    rustc  = @('--version')
    cargo  = @('--version')
    rustup = @('show', 'active-toolchain')
    java   = @('-version')
    javac  = @('-version')
    dotnet = @('--version')
    gcc    = @('--version')
    'g++'  = @('--version')
    gdb    = @('--version')
    make   = @('--version')
    'mingw32-make' = @('--version')
    cmake  = @('--version')
    git    = @('--version')
    gh     = @('--version')
    dlltool= @('--version')
}
foreach ($exe in $probes.Keys) {
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $toolchains[$exe] = [ordered]@{ Found = $false }
        Row $exe 'NOT FOUND'
        continue
    }
    $first = $null
    try { $first = (& $cmd.Source @($probes[$exe]) 2>&1 | Where-Object { $_ } | Select-Object -First 1) } catch {}
    $toolchains[$exe] = [ordered]@{
        Found   = $true
        Path    = $cmd.Source
        Version = "$first"
    }
    Row $exe "$first"
}
# dlltool is called by the GNU Rust target when linking; missing it produces a
# confusing "error calling dlltool 'dlltool.exe': program not found" at build time.
$toolchains['dlltool_Note'] = 'dlltool is required by rustc for x86_64-pc-windows-gnu'
$report.Toolchains = $toolchains

# ----------------------------------------------------------------- PATH
Section 'PATH entries'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$procPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
$userParts = @($userPath -split ';' | Where-Object { $_ })
$machineParts = @($machinePath -split ';' | Where-Object { $_ })
$dupes = @($userParts | Group-Object | Where-Object Count -gt 1)
$missing = @($userParts | Where-Object { -not (Test-Path $_) })
$report.Path = [ordered]@{
    UserCount    = $userParts.Count
    MachineCount = $machineParts.Count
    Duplicates   = @($dupes | ForEach-Object { $_.Name })
    NonExistent  = $missing
    ProcessHasUserPath = ($procPath -like "*$($userParts[0])*")
}
foreach ($p in $userParts) {
    $state = if (Test-Path $p) { 'ok  ' } else { 'MISS' }
    if (-not $Json) { "  [$state] $p" }
}
if ($dupes) { Row 'duplicates' (($dupes | ForEach-Object { $_.Name }) -join ' | ') }
if ($missing) { Row 'non-existent' ($missing -join ' | ') }

# ----------------------------------------------------------------- env vars
Section 'Persisted user environment variables'
$interesting = @(
    'JAVA_HOME','DOTNET_ROOT','MSBuildSDKsPath','GOPATH','GOROOT','GOPROXY','GOSUMDB',
    'CARGO_HOME','RUSTUP_HOME','RUSTUP_DIST_SERVER','RUSTUP_UPDATE_ROOT',
    'NPM_CONFIG_REGISTRY','ELECTRON_MIRROR','SASS_BINARY_SITE','PIP_INDEX_URL',
    'PYTHONUTF8','PYTHONIOENCODING','GCM_CREDENTIAL_STORE','SSH_AUTH_SOCK','CUA_DRIVER_BIN'
)
$envVars = [ordered]@{}
foreach ($n in $interesting) {
    $v = [Environment]::GetEnvironmentVariable($n, 'User')
    $envVars[$n] = $v
    if ($v) { Row $n $v } else { Row $n '<unset>' }
}
$report.UserEnv = $envVars

# ----------------------------------------------------------------- package managers
Section 'Package managers'
$pm = [ordered]@{}
foreach ($name in $PackageManagers) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    $pm[$name] = [ordered]@{ Found = [bool]$cmd; Path = if ($cmd) { $cmd.Source } else { $null } }
}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    try {
        $apps = @(& scoop list 2>&1)
        $pm['scoop']['Apps'] = $apps.Count - 1
        if (-not $Json) { Write-Output "  scoop apps:"; $apps | Select-Object -Skip 1 | ForEach-Object { "    $_" } }
    } catch {}
    try {
        $cache = @(& scoop cache show 2>&1)
        $pm['scoop']['CacheEntries'] = $cache.Count
        if (-not $Json) { Write-Output "  scoop cache entries: $($cache.Count)" }
    } catch {}
    # scoop itself lives outside the profile root; the shims dir must be on PATH
    # or no scoop-installed command is reachable from a fresh shell.
    $shims = Join-Path $env:USERPROFILE 'scoop\shims'
    $pm['scoop']['ShimsOnUserPath'] = ($userParts -contains $shims)
    if (-not $Json) { Write-Output "  shims on user PATH: $($userParts -contains $shims)  ($shims)" }
}
$report.PackageManagers = $pm
foreach ($k in $pm.Keys) { if (-not $Json) { Row $k $(if ($pm[$k].Found) { $pm[$k].Path } else { 'NOT FOUND' }) } }

# ----------------------------------------------------------------- disk
Section 'Disk usage'
$disk = [ordered]@{}
try {
    $drive = Get-PSDrive C -ErrorAction Stop
    $disk['CFreeGB'] = [math]::Round($drive.Free / 1GB, 1)
    $disk['CUsedGB'] = [math]::Round($drive.Used / 1GB, 1)
} catch {}
$paths = @(
    "$env:USERPROFILE\scoop",
    "$env:USERPROFILE\.rustup",
    "$env:USERPROFILE\.cargo",
    "$env:USERPROFILE\go",
    "$env:USERPROFILE\.nuget",
    "$env:USERPROFILE\.dotnet",
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Local\pip\cache",
    "$env:USERPROFILE\.cargo\registry"
)
foreach ($p in $paths) {
    if (Test-Path $p) {
        try {
            $sum = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum
            $mb = [math]::Round($sum / 1MB, 0)
            $disk[$p.Replace($env:USERPROFILE, '~')] = $mb
            if (-not $Json) { '  {0,-52} {1,8} MB' -f $p.Replace($env:USERPROFILE, '~'), $mb | Write-Output }
        } catch {}
    }
}
$report.Disk = $disk

# ----------------------------------------------------------------- mirrors
Section 'Mirror reachability'
$mirrors = [ordered]@{
    'pypi-tuna'   = 'https://pypi.tuna.tsinghua.edu.cn/simple/'
    'npmmirror'   = 'https://registry.npmmirror.com'
    'goproxy.cn'  = 'https://goproxy.cn'
    'rsproxy'     = 'https://rsproxy.cn/index/'
    'nuget-huawei'= 'https://repo.huaweicloud.com/repository/nuget/v3/index.json'
    'github'      = 'https://github.com'
}
foreach ($k in $mirrors.Keys) {
    $url = $mirrors[$k]
    $status = 'FAIL'
    try {
        $r = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 12 -UseBasicParsing -ErrorAction Stop
        $status = "$($r.StatusCode)"
    } catch { $status = "FAIL: $($_.Exception.Message.Split("`n")[0])" }
    $mirrors[$k] = [ordered]@{ Url = $url; Status = $status }
    Row $k "$status  $url"
}
$report.Mirrors = $mirrors

# ----------------------------------------------------------------- DNS sanity
Section 'DNS resolution (common dev hosts)'
$hosts = @('github.com','nodejs.org','static.rust-lang.org','pypi.org','registry.npmjs.org','go.dev','cdn.npmmirror.com')
$dns = [ordered]@{}
foreach ($h in $hosts) {
    try {
        $ips = @(Resolve-DnsName $h -Type A -QuickTimeout -ErrorAction Stop |
                 Where-Object { $_.IPAddress } | Select-Object -First 2 -ExpandProperty IPAddress)
        $dns[$h] = @($ips)
        Row $h ($ips -join ', ')
    } catch {
        $dns[$h] = @()
        Row $h 'RESOLVE FAIL'
    }
}
$report.Dns = $dns

# ----------------------------------------------------------------- output
if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Output "`n===== audit complete ====="
    Write-Output "No changes were made. Feed this report to fix-env.ps1 / setup-langs.ps1."
}
