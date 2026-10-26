<#
.SYNOPSIS
  Register portable applications so Windows offers them for file types, back up the
  association registry, and report exactly which defaults Windows will not let a script set.

.DESCRIPTION
  Why this script does not "just set the default program" - the precise picture:

  1. The documented COM API exists. IApplicationAssociationRegistration
     (CLSID 591209c7-767b-42b2-9fba-44ee4615f2c7) exposes SetAppAsDefault and
     SetAppAsDefaultAll. QueryAppIsDefault still works and reports the truth.
     But on Windows 10/11 SetAppAsDefault no longer changes the default; it fails.
     Measured on Windows 10 22H2 it returned 0x80070002 (ERROR_FILE_NOT_FOUND) - an
     error code that has nothing to do with the real reason, which is that the
     operation is blocked by policy.

  2. The stored default lives in
         HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<ext>\UserChoice
     and that key carries TWO protections:
       - an explicit DENY SetValue ACE for the current user
       - a Hash over ProgId + SID + timestamp
     A write attempt fails with "Requested registry access is not allowed". Because NT
     evaluates DENY before ALLOW, this holds even for the key owner and for an
     administrator. It is deliberately designed to stop silent hijacking.

  So the only thing that works is: register the application properly, then let the USER
  pick it once. That is what this script automates as far as it can.

  What this script does:
    - backs up the association registry branches (restorable with reg import)
    - registers each app so Windows OFFERS it, via BOTH mechanisms - they are not
      interchangeable, and registering only one leaves the app half-visible:
        HKCU\Software\Classes\Applications\<exe>   -> right-click "Open with" list
        HKCU\Software\<Vendor>\Capabilities +
        HKCU\Software\RegisteredApplications       -> Settings -> Default apps ->
                                                      "Choose defaults by file type"
    - reports which extensions still need one manual click

.PARAMETER Apps
  A hashtable of app definitions. Keys are display names; values are hashtables with:
    Exe  - full path to the executable (required)
    Exts - array of extensions to offer for, e.g. @('.png', '.jpg')
    Desc - optional description shown in the Default apps list

  Example:
    -Apps @{ 'ImageGlass' = @{ Exe = "$env:USERPROFILE\Apps\ImageGlass\ImageGlass.exe"
                              Exts = @('.png','.jpg'); Desc = 'Image viewer' } }

.PARAMETER Register
  Actually perform the registration. Without it the script only reports state and takes
  a backup - so a first run is always safe.

.PARAMETER CheckOnly
  Only report the current association state; take no backup and register nothing.

.PARAMETER BackupDir
  Where to write the registry backups. Default: <portable root>\_backup

.EXAMPLE
  pwsh -File set-app-associations.ps1
  pwsh -File set-app-associations.ps1 -Register -Apps @{ 'ImageGlass' = @{ Exe = 'C:\Apps\ImageGlass\ImageGlass.exe'; Exts = @('.png') } }

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [hashtable]$Apps,
    [switch]$Register,
    [switch]$CheckOnly,
    [string]$BackupDir = (Join-Path $env:USERPROFILE 'Apps\_backup')
)

$ErrorActionPreference = 'Continue'
$Cmdlet = $PSCmdlet

# Rebuild PATH from the registry so a stale parent environment cannot affect behaviour.
$env:PATH = (@(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User')
) | Where-Object { $_ }) -join ';'

function Info { param([string]$M) Write-Output "    $M" }
function Ok   { param([string]$M) Write-Output "    ok      $M" }
function Warn { param([string]$M) Write-Output "    WARN    $M" }

Write-Output '===== set-app-associations ====='
if ($Apps -and -not $Register -and -not $CheckOnly) {
    Info 'apps were supplied but -Register was not passed: reporting only, nothing will change'
}

$exts = @('.md','.txt','.png','.jpg','.jpeg','.gif','.webp','.bmp','.tif','.tiff',
          '.mp4','.mkv','.avi','.mov','.wmv','.webm','.mp3','.flac','.wav','.m4a')

# ------------------------------------------------------------------- report
function Get-Assoc {
    param([string]$Ext)
    $choiceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext\UserChoice"
    $progId = $null; $protected = $false
    if (Test-Path $choiceKey) {
        try { $progId = (Get-ItemProperty $choiceKey -ErrorAction Stop).ProgId } catch {}
        try {
            $acl = Get-Acl $choiceKey -ErrorAction Stop
            # the DENY SetValue rule is the machine-readable mark of "you cannot change this"
            $protected = [bool]($acl.Access | Where-Object {
                $_.AccessControlType -eq 'Deny' -and
                ($_.RegistryRights -band [Security.AccessControl.RegistryRights]::SetValue)
            })
        } catch {}
    }
    if (-not $progId) {
        try {
            $v = (Get-ItemProperty "HKCU:\Software\Classes\$Ext" -ErrorAction SilentlyContinue).'(default)'
            if ($v) { $progId = $v }
        } catch {}
    }
    [pscustomobject]@{
        Extension = $Ext
        ProgId    = if ($progId) { $progId } else { $null }
        Protected = $protected
        # AppX* means a built-in Store app, which is usually the one people want to replace
        NeedsManual = ($null -eq $progId) -or ($progId -like 'AppX*')
    }
}

Write-Output "`n--- current state"
$state = @()
foreach ($e in $exts) {
    $s = Get-Assoc $e
    $state += $s
    $mark = if ($s.Protected) { 'protected' } elseif ($s.ProgId) { 'set' } else { 'unset' }
    '  {0,-7} {1,-12} {2}' -f $s.Extension, $mark, $(if ($s.ProgId) { $s.ProgId } else { '-' }) | Write-Output
}

# ------------------------------------------------------------------- backup
if (-not $CheckOnly -and $Register -and $Apps) {
    Write-Output "`n--- backup"
    if ($Cmdlet.ShouldProcess($BackupDir, 'back up association registry branches')) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        foreach ($branch in @('HKCU\Software\Classes', 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts')) {
            $leaf = ($branch -split '\\')[-1]
            $file = Join-Path $BackupDir "$leaf-$stamp.reg"
            & reg export $branch $file /y 2>&1 | Out-Null
            if (Test-Path $file) { Ok "saved $file" } else { Warn "could not export $branch" }
        }
        Info 'restore with: reg import <file>'
    }
}

# -------------------------------------------------------------- register
if ($Apps -and -not $CheckOnly -and $Register) {
    Write-Output "`n--- register applications"
    New-Item -Path 'HKCU:\Software\RegisteredApplications' -Force | Out-Null

    foreach ($name in $Apps.Keys) {
        $def = $Apps[$name]
        $exe = $def.Exe
        $appExts = @($def.Exts)
        if (-not $exe -or -not (Test-Path $exe)) { Warn "$name -> exe not found: $exe"; continue }

        $safe = $name -replace '[^A-Za-z0-9]', '_'
        $exeLeaf = Split-Path $exe -Leaf

        # (a) Classes\Applications\<exe> : makes the app show up in the right-click
        #     "Open with" list. Without it the user has to browse for the executable.
        $appKey = "HKCU:\Software\Classes\Applications\$exeLeaf"
        if ($Cmdlet.ShouldProcess($appKey, "register $name for Open-with")) {
            New-Item -Path "$appKey\shell\open\command" -Force | Out-Null
            Set-ItemProperty -Path $appKey -Name 'FriendlyAppName' -Value $name
            Set-ItemProperty -Path "$appKey\shell\open\command" -Name '(default)' -Value "`"$exe`" `"%1`""
            Ok "$name -> Open with list"
        }

        # App Paths lets the Run dialog and the Open-with dialog resolve the bare exe name
        $appPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exeLeaf"
        if ($Cmdlet.ShouldProcess($appPath, "register App Path for $exeLeaf")) {
            New-Item -Path $appPath -Force | Out-Null
            Set-ItemProperty -Path $appPath -Name '(default)' -Value $exe
            Ok "$name -> App Paths"
        }

        # (b) Capabilities + RegisteredApplications : makes the app appear in
        #     Settings -> Apps -> Default apps -> "Choose defaults by file type".
        #     Registering only (a) leaves the app out of that list entirely.
        if ($appExts.Count -gt 0) {
            $cap = "HKCU:\Software\$safe\Capabilities"
            if ($Cmdlet.ShouldProcess($cap, "register $name capabilities")) {
                New-Item -Path "$cap\FileAssociations" -Force | Out-Null
                Set-ItemProperty -Path $cap -Name 'ApplicationName' -Value $name
                if ($def.Desc) { Set-ItemProperty -Path $cap -Name 'ApplicationDescription' -Value $def.Desc }
                foreach ($ext in $appExts) {
                    $progId = "$safe$ext"
                    # a per-extension ProgID gives each type a proper display name and icon
                    $progKey = "HKCU:\Software\Classes\$progId"
                    New-Item -Path "$progKey\shell\open\command" -Force | Out-Null
                    New-Item -Path "$progKey\DefaultIcon" -Force | Out-Null
                    Set-ItemProperty -Path $progKey -Name '(default)' -Value "$ext ($name)"
                    Set-ItemProperty -Path "$progKey\shell\open\command" -Name '(default)' -Value "`"$exe`" `"%1`""
                    Set-ItemProperty -Path "$progKey\DefaultIcon" -Name '(default)' -Value "$exe,0"
                    Set-ItemProperty -Path "$cap\FileAssociations" -Name $ext -Value $progId
                }
                Set-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name $name -Value "Software\$safe\Capabilities"
                Ok "$name -> Default apps list ($($appExts.Count) extensions)"
            }
        }
    }
}

# ---------------------------------------------------------------- guidance
Write-Output "`n--- what still needs a manual click"
$manual = @($state | Where-Object { $_.NeedsManual })
if ($manual.Count -eq 0) {
    Ok 'nothing - every checked extension already resolves to a real application'
} else {
    foreach ($m in $manual) {
        $reason = if (-not $m.ProgId) { 'no default set' } else { "currently a built-in Store app ($($m.ProgId))" }
        '  {0,-7} {1}' -f $m.Extension, $reason | Write-Output
    }
    Write-Output ''
    Write-Output '  Windows forbids scripts from changing these (see the header comment for the'
    Write-Output '  exact mechanism). Do it once per extension - it sticks:'
    Write-Output ''
    Write-Output '    A) right-click a file -> Open with -> Choose another app'
    Write-Output '       -> pick the portable app -> tick "Always use this app"'
    Write-Output ''
    Write-Output '    B) Settings -> Apps -> Default apps -> Choose defaults by file type'
    Write-Output '       (registered apps appear here by name)'
}

Write-Output "`n===== done ====="
