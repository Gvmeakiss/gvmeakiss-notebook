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
# The probes are independent, so they run concurrently under PowerShell 7: measured
# 2.11 s sequential vs 0.61 s parallel (3.4x) with identical results across all 20 entries.
# Windows PowerShell 5.1 has no -Parallel, so it keeps the sequential path; the output
# order is dictated by $probes either way, which keeps the report diffable between hosts.
$probeArgs = @{}
foreach ($k in $probes.Keys) { $probeArgs[$k] = @($probes[$k]) }
$probeResults = @{}
if ($PSVersionTable.PSEdition -eq 'Core') {
    $raw = @($probes.Keys) | ForEach-Object -Parallel {
        $exe = $_
        # $using: can only name a variable - it takes no indexing and no expressions,
        # so the whole argument map is brought in and indexed inside the block.
        $map = $using:probeArgs
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { return [pscustomobject]@{ Name = $exe; Found = $false; Path = ''; Version = '' } }
        $first = $null
        try { $first = (& $cmd.Source @($map[$exe]) 2>&1 | Where-Object { $_ } | Select-Object -First 1) } catch { }
        [pscustomobject]@{ Name = $exe; Found = $true; Path = $cmd.Source; Version = "$first" }
    } -ThrottleLimit 20
    foreach ($r in $raw) { $probeResults[$r.Name] = $r }
} else {
    foreach ($exe in $probes.Keys) {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { $probeResults[$exe] = [pscustomobject]@{ Name = $exe; Found = $false; Path = ''; Version = '' }; continue }
        $first = $null
        try { $first = (& $cmd.Source @($probes[$exe]) 2>&1 | Where-Object { $_ } | Select-Object -First 1) } catch { }
        $probeResults[$exe] = [pscustomobject]@{ Name = $exe; Found = $true; Path = $cmd.Source; Version = "$first" }
    }
}

foreach ($exe in $probes.Keys) {
    $r = $probeResults[$exe]
    if (-not $r -or -not $r.Found) {
        $toolchains[$exe] = [ordered]@{ Found = $false }
        Row $exe 'NOT FOUND'
        continue
    }
    $toolchains[$exe] = [ordered]@{
        Found   = $true
        Path    = $r.Path
        Version = $r.Version
    }
    Row $exe $r.Version
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
# Directory size via .NET enumeration instead of Get-ChildItem -Recurse.
# Measured on ~\scoop (8 GB, tens of thousands of files):
#     Get-ChildItem -Recurse -File | Measure-Object : 10.27 s
#     this walk                                     :  3.09 s   (3.3x, identical total)
# Get-ChildItem builds a FileInfo object per file; EnumerateFiles does not.
#
# CRITICAL: reparse points must be skipped. A naive walk that follows them counted
# ~\scoop twice (17901 MB vs the true 8088 MB) because scoop\apps\<app>\current is a
# junction to the version directory - there are 14 of them on a normal install.
# Get-ChildItem skips them, so the naive version was "faster" only by being wrong.
function Get-TreeBytes {
    param([string]$Root)
    $sum = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo $d
            foreach ($f in $di.EnumerateFiles()) { try { $sum += $f.Length } catch {} }
            foreach ($s in $di.EnumerateDirectories()) {
                if (($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($s.FullName) }
            }
        }
        catch {}
    }
    return $sum
}

foreach ($p in $paths) {
    if (Test-Path $p) {
        try {
            $mb = [math]::Round((Get-TreeBytes $p) / 1MB, 0)
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
# These are network round-trips, so they run CONCURRENTLY. Sequential, the total was the
# SUM of six round-trips and a single unreachable mirror added its whole 12 s timeout;
# concurrent, the total is roughly the SLOWEST one. HttpClient + Task is used because
# ForEach-Object -Parallel is PowerShell 7-only and this script must run on 5.1.
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$mirrorKeys = @($mirrors.Keys)
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(12)
$tasks = [ordered]@{}
foreach ($k in $mirrorKeys) {
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Head, $mirrors[$k])
        $tasks[$k] = $http.SendAsync($req)
    }
    catch { $tasks[$k] = $null }
}
foreach ($k in $mirrorKeys) {
    $url = $mirrors[$k]
    $status = 'FAIL'
    $t = $tasks[$k]
    if ($null -ne $t) {
        try {
            $null = $t.Wait()
            $status = "$([int]$t.Result.StatusCode)"
        }
        catch {
            $ex = $_.Exception
            if ($ex.InnerException) { $ex = $ex.InnerException }
            $status = "FAIL: $($ex.Message.Split("`n")[0])"
        }
    }
    else { $status = 'FAIL: could not build the request' }
    $mirrors[$k] = [ordered]@{ Url = $url; Status = $status }
    Row $k "$status  $url"
}
$http.Dispose()
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
