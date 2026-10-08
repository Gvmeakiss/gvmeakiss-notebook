<#
.SYNOPSIS
  Prepare file associations for portable applications, and report exactly which ones
  Windows will not let a script set.

.DESCRIPTION
  Why this script does not "just set the default program":

  Windows 10/11 stores each user's default app in
      HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\<ext>\UserChoice
  and that key carries BOTH of these protections:
    1. an explicit DENY SetValue ACE for the current user
    2. a Hash value over the ProgId + SID + timestamp
  A write attempt fails with "Requested registry access is not allowed". This is
  deliberate - it stops software from silently hijacking your defaults. It also means
  no script, admin or not, can change a default app for you.

  What a script CAN do, and what this one does:
    - back up the association-related registry branches first
    - register a ProgID under HKCU\Software\Classes so the app appears in the
      "Open with" list and becomes selectable
    - tell you precisely which extensions still need one manual click

.PARAMETER Register
  ProgID names to register as selectable handlers, as name=exe path pairs,
  e.g. -Register @{ 'MarkdownFile' = 'C:\Apps\Notepad++\notepad++.exe' }

.PARAMETER CheckOnly
  Only report the current association state. This is the default behaviour.

.EXAMPLE
  pwsh -File set-app-associations.ps1
  pwsh -File set-app-associations.ps1 -Register @{ 'MdEditor' = "$env:USERPROFILE\Apps\MarkText\marktext.exe" }

.NOTES
  ASCII-only on purpose.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [hashtable]$Register,
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

$exts = @('.md','.txt','.png','.jpg','.jpeg','.gif','.webp','.bmp','.mp4','.mkv','.avi','.mov','.mp3','.flac','.wav')

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
if (-not $CheckOnly) {
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
if ($Register -and -not $CheckOnly) {
    Write-Output "`n--- register handlers"
    foreach ($progId in $Register.Keys) {
        $exe = $Register[$progId]
        if (-not (Test-Path $exe)) { Warn "$progId -> exe not found: $exe"; continue }
        $key = "HKCU:\Software\Classes\$progId"
        if ($Cmdlet.ShouldProcess($key, 'register ProgID')) {
            New-Item -Path $key -Force | Out-Null
            Set-ItemProperty -Path $key -Name '(default)' -Value $progId
            New-Item -Path "$key\shell\open\command" -Force | Out-Null
            # %1 is substituted with the clicked file path
            Set-ItemProperty -Path "$key\shell\open\command" -Name '(default)' -Value "`"$exe`" `"%1`""
            Ok "registered $progId -> $exe"
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
    Write-Output '  Windows forbids scripts from changing these. Do it once per extension:'
    Write-Output '    right-click a file -> Open with -> Choose another app'
    Write-Output '    -> pick the portable app -> tick "Always use this app"'
    Write-Output ''
    Write-Output '  Alternatively: Settings -> Apps -> Default apps -> Choose defaults by file type.'
    Write-Output '  This is a one-time action per extension, and it sticks.'
}

Write-Output "`n===== done ====="
