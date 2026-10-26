# verify-env section: tune tweaks survival - dot-sourced by verify-env.ps1 in order.
# Kept in its own file so the acceptance suite is a list of sections rather than one 850-line
# script. `$here` (not `$PSScriptRoot`) is used inside: $PSScriptRoot would point at lib/verify.

# ------------------------------------------------------------------ tune tweaks survival
# Why this section exists: a cumulative update silently reverts the tune phase.
# Two rules learned the hard way, both encoded below.
#   1. The update DELETES these values rather than changing them. So "missing"
#      must count as FAIL, not be read as "this machine never had it set".
#      Checking only the value would let a deleted setting pass unnoticed.
#   2. For MMCSS, reading the registry is not evidence. The driver can sit at
#      START_TYPE=2 AUTO_START while STATE=STOPPED (exit code 1341); the values
#      are then inert. Only `sc query` showing RUNNING means it actually works.
Write-Output "`n--- tune tweaks (did they survive a Windows Update?)"
$keyCache = @{}
$tweaks = @(
    @{ Check = 'GameDVR policy';        Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';                        Name = 'AllowGameDVR';                    Want = '0' },
    @{ Check = 'GameDVR user';          Path = 'HKCU:\System\GameConfigStore';                                            Name = 'GameDVR_Enabled';                 Want = '0' },
    @{ Check = 'MMCSS responsiveness';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness';          Want = '10' },
    @{ Check = 'MMCSS net throttling';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex';         Want = '4294967295' },
    @{ Check = 'MMCSS GPU priority';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority';       Want = '8' },
    @{ Check = 'MMCSS sched category';  Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Want = 'High' },
    @{ Check = 'consumer features off'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                   Name = 'DisableWindowsConsumerFeatures';  Want = '1' },
    @{ Check = 'silent app installs';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SilentInstalledAppsEnabled';      Want = '0' },
    @{ Check = 'start suggestions';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SystemPaneSuggestionsEnabled';    Want = '0' },
    @{ Check = 'soft landing tips';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SoftLandingEnabled';              Want = '0' },
    @{ Check = 'explorer sync ads';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';         Name = 'ShowSyncProviderNotifications';   Want = '0' },
    # The Start-menu web-search switch exists in TWO places, and which one is settable is
    # build/product dependent. Measured on Windows 11 24H2+: writes to the
    # `...\CurrentVersion\Search` key are refused at kernel level ("not all data was
    # successfully written") while its ACL still shows the user FullControl, so the tune
    # phase cannot land BingSearchEnabled/CortanaConsent there at all. The official policy
    # route below always worked. Scoring these as a pair means either route counts as done -
    # a one-path check reports a permanent false FAIL on the machines where the key is locked.
    @{ Check = 'bing web search';       Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                   Name = 'BingSearchEnabled';               Want = '0'
       AltPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';                                                     AltName = 'DisableSearchBoxSuggestions';  AltWant = '1'
       AltWhy = 'policy route (the Search key can be kernel-protected; policy wins over user scope anyway)' },
    @{ Check = 'web search policy';     Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                 Name = 'ConnectedSearchUseWeb';           Want = '0'
       AltWhy = 'machine-wide: no web results in Start search' },
    # AllowTelemetry expects the strictest value the SKU honours, not a flat 0. 0 (Security/Off)
    # is only accepted on Enterprise / Education / Server; Home and Pro silently ignore it, so a
    # flat Want='0' would report FAIL on a correctly configured Pro box (or PASS on a box that
    # wrote a value Windows never reads - measured: Win11 Pro carried AllowTelemetry=0 and still
    # uploaded diagnostics).
    # Safety nets and network/disk housekeeping added after the evidence review. Each one is a
    # write that setup.ps1 -Phase tune performs, and a write with no check is an unchecked claim.
    # NOTE: EnablePeriodicBackup is deliberately NOT checked here as a registry value. Measured
    # on Windows 11 26xxx: the value reads back as 1, the RegIdleBackup task exists but has NO
    # trigger and NO action, the SIT service no longer exists, and the hives in
    # C:\Windows\System32\config\RegBack stay 0 bytes. Checking the switch would report a safety
    # net that does not exist - the outcome is checked as 'registry hive backup' further down.
    @{ Check = 'bitlocker auto-encrypt'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker';                            Name = 'PreventDeviceEncryption'; Want = '1'
       AltWhy = 'future automatic device encryption blocked (existing volumes untouched)' },
    @{ Check = 'delivery optimization'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'; Name = 'DODownloadMode';            Want = '1'
       AltWhy = 'updates stay on the LAN instead of uploading to the internet' },
    @{ Check = 'recycle bin cleanup';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '08';               Want = '1'
       AltWhy = 'Storage Sense empties the recycle bin' },
    @{ Check = 'recycle retention';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '32';               Want = '30'
       AltWhy = 'recycle bin retention: 30 days' },
    @{ Check = 'wpbt blocked';          Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager';                    Name = 'DisableWpbtExecution'; Want = '1'
       AltWhy = 'no OEM firmware-injected executables at boot' },
    @{ Check = 'device metadata off';   Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata';                   Name = 'PreventDeviceMetadataFromNetwork'; Want = '1'
       AltWhy = 'no companion-app push when a device is plugged in' },
    @{ Check = 'registry backup depth'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'BackupCount'; Want = '2'
       AltWhy = 'two hive-backup generations kept' },
    @{ Check = 'background apps off';   Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Want = '1'
       AltWhy = 'Store apps cannot run in the background' },
    @{ Check = 'welcome splash off';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';     Name = 'SubscribedContent-310093Enabled'; Want = '0'
       AltWhy = 'no post-update what-is-new splash' },
    @{ Check = 'lock screen toasts off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications';         Name = 'LockScreenToastEnabled'; Want = '0'
       AltWhy = 'no notification content on the lock screen' },
    @{ Check = 'toasts above lock off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings';     Name = 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK'; Want = '0'
       AltWhy = 'same switch, per-user scope' },
    @{ Check = 'advertising id off';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';          Name = 'Enabled'; Want = '0'
       AltWhy = 'no per-user advertising ID' },
    @{ Check = 'tailored tips off';     Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy';                  Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Want = '0'
       AltWhy = 'no diagnostic-data-derived personalisation' },
    @{ Check = 'activity upload off';   Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                          Name = 'PublishUserActivities'; Want = '0'
       AltWhy = 'timeline does not upload activity history' },
    @{ Check = 'activity feed off';     Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                          Name = 'EnableActivityFeed'; Want = '0'
       AltWhy = 'same policy family' },
    @{ Check = 'input personalization off'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization';                Name = 'AllowInputPersonalization'; Want = '0'
       AltWhy = 'typing/inking data not sent for personalisation' },
    @{ Check = 'cloud speech off';      Path = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy';      Name = 'HasAccepted'; Want = '0'
       AltWhy = 'online speech consent withdrawn' },
    @{ Check = 'edge startup boost off'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                   Name = 'StartupBoostEnabled'; Want = '0'
       AltWhy = 'Edge keeps no preloaded background processes' },
    # The nine values below were written by tune but had no acceptance check, so a silent
    # regression (a value deleted by an update, or never written because a key was refused)
    # would have gone unnoticed. A write with no check is an unchecked claim.
    @{ Check = 'MMCSS game priority';   Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Want = '6'
       AltWhy = 'game task CPU priority' },
    @{ Check = 'MMCSS sfio priority';   Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Want = 'High'
       AltWhy = 'game task storage IO priority' },
    @{ Check = 'start recommendations off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Want = '0'
       AltWhy = 'no Start-menu recommendations' },
    @{ Check = 'welcome suggestions off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Want = '0'
       AltWhy = 'no post-setup welcome suggestions' },
    @{ Check = 'timeline suggestions off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Want = '0'
       AltWhy = 'no timeline suggestion prompts' },
    @{ Check = 'lock screen overlay off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Want = '0'
       AltWhy = 'no promotional overlay on the lock screen' },
    @{ Check = 'preinstalled promo off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Want = '0'
       AltWhy = 'no preinstalled-app promotion' },
    @{ Check = 'oem promo off';         Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Want = '0'
       AltWhy = 'no OEM app promotion' },
    @{ Check = 'cortana consent off';   Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                 Name = 'AllowCortana'; Want = '0'
       AltWhy = 'no cloud search consent' },
    @{ Check = 'game mode on';          Path = 'HKCU:\Software\Microsoft\GameBar';                                         Name = 'AutoGameModeEnabled'; Want = '1'
       AltWhy = 'Game Mode pinned on' },

    @{ Check = 'cloud files in quick access off'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer';        Name = 'ShowCloudFilesInQuickAccess'; Want = '0'
       AltWhy = 'no Office.com cloud query on Explorer open' },
    @{ Check = 'default printer pinned'; Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows';               Name = 'LegacyDefaultPrinterMode'; Want = '1'
       AltWhy = 'Windows stops switching the default printer by itself' },
    @{ Check = 'telemetry policy';      Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';                 Name = 'AllowTelemetry'
       Want = $(if ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID' -ErrorAction SilentlyContinue).EditionID -match 'Enterprise|Education|Server') { '0' } else { '1' })
       AltWhy = 'strictest level the edition honours (0 is Enterprise/Education-only)' }
)
foreach ($t in $tweaks) {
    # Read each KEY once and look every value up inside it, instead of one Get-ItemProperty
    # per value. Measured on 30 values: per-value = 154 ms, per-key = 4 ms (~35x).
    $get = {
        param($p)
        if (-not $keyCache.ContainsKey($p)) {
            $keyCache[$p] = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
        }
        return $keyCache[$p]
    }
    $props = & $get $t.Path
    $have  = ($null -ne $props) -and ($null -ne $props.($t.Name))
    $val   = if ($have) { "$($props.($t.Name))" } else { $null }
    $ok    = $have -and ($val -eq $t.Want)
    $altOk = $false
    $altVal = $null
    if (-not $ok -and $t.ContainsKey('AltPath')) {
        $altProps = & $get $t.AltPath
        $altHave  = ($null -ne $altProps) -and ($null -ne $altProps.($t.AltName))
        $altVal   = if ($altHave) { "$($altProps.($t.AltName))" } else { $null }
        $altOk    = $altHave -and ($altVal -eq $t.AltWant)
    }
    $ok = $ok -or $altOk
    $detail = if ($altOk) { "=$altVal via $($t.AltName) - $($t.AltWhy)" }
              elseif (-not $have) { 'VALUE MISSING - re-run: setup.ps1 -Phase tune. If several values in ONE key are missing but the last-written one is present, the cause is the New-Item -Force bug, not a cumulative update (see SKILL.md)' }
              elseif (-not $ok) { "actual=$val want=$($t.Want)" }
              else { "=$val" }
    Record 'tweaks' $t.Check $ok $detail
}
# The classic context menu is toggled through the DEFAULT value of a CLSID key, which the
# table above cannot express (it looks values up by name). Absent key = the Win11 folded menu.
$ctxKey = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
$ctxVal = (Get-ItemProperty -Path $ctxKey -ErrorAction SilentlyContinue).'(default)'
$ctxDetail = if ($null -eq $ctxVal) { 'override key absent - the Win11 folded menu is in use' } else { "InprocServer32 default='$ctxVal'" }
Record 'tweaks' 'classic context menu' ($ctxVal -eq '') $ctxDetail

# Registry hive backup - checks the OUTCOME, not the switch. setup.ps1 sets
# EnablePeriodicBackup=1 and enables RegIdleBackup, but on Windows 11 26xxx both are vestigial:
# the task has no trigger and no action, the SIT service is gone, and RegBack holds 0-byte files.
# Measured after a reboot AND after manually starting the task: still 0 bytes.
# Informational: the value lands, the hives appear later, and until they do the restore point is
# the guaranteed undo path.
$regBack = 'C:\Windows\System32\config\RegBack'
$regBackBytes = 0
if (Test-Path $regBack) {
    $regBackBytes = @(Get-ChildItem $regBack -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $regBackBytes) { $regBackBytes = 0 }
}
$regBackDetail = if (-not (Test-Path $regBack)) { 'RegBack folder absent' }
                 elseif ($regBackBytes -gt 1MB) { "hive copies present ($([math]::Round($regBackBytes/1MB,1)) MB)" }
                 else { "not populated yet ($regBackBytes byte(s)): Windows fills RegBack at a later boot/idle point, not on demand (measured 0 bytes right after enabling, 110 MB two days later) - rely on the restore point until then" }
Record 'tweaks' 'registry hive backup' ($regBackBytes -gt 1MB) $regBackDetail -Optional

# Telemetry scheduled tasks: informational because the list is build-dependent. Measured on
# this build: "Microsoft Compatibility Appraiser" and "ProgramDataUpdater" do not exist, so a
# hard expectation would be a permanent false FAIL.
$telList = @(
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
    @{ Path = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
    @{ Path = '\Microsoft\Windows\DiskDiagnostic\'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
    @{ Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' }
)
$telPresent = 0; $telStillOn = @()
foreach ($t in $telList) {
    $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
    if (-not $task) { continue }
    $telPresent++
    if ($task.State -ne 'Disabled') { $telStillOn += $t.Name }
}
Record 'tweaks' 'telemetry tasks' ($telStillOn.Count -eq 0) $(
    if ($telPresent -eq 0) { 'no known telemetry tasks on this build' }
    elseif ($telStillOn.Count -eq 0) { "$telPresent present, all disabled" }
    else { "$($telStillOn.Count)/$telPresent still enabled: $($telStillOn -join ', ')" }) -Optional

# DiagTrack egress: recommendable by firewall group. Informational since the group may not
# exist on every build.
$diagRules = @(Get-NetFirewallRule -Group 'DiagTrack' -ErrorAction SilentlyContinue)
$diagBlocked = @($diagRules | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
Record 'tweaks' 'diagtrack firewall' ($diagRules.Count -gt 0 -and $diagBlocked.Count -eq $diagRules.Count) $(
    if ($diagRules.Count -eq 0) { 'no DiagTrack firewall group on this build' }
    else { "$($diagBlocked.Count)/$($diagRules.Count) rule(s) blocked" }) -Optional

$mmcssOut = sc.exe query MMCSS 2>&1 | Out-String
$mmcssUp  = $mmcssOut -match 'RUNNING'
Record 'tweaks' 'MMCSS driver running' $mmcssUp $(
    if ($mmcssUp) { 'RUNNING - the MMCSS values above are actually in effect' }
    else { 'STOPPED - values above are INERT. Run: sc.exe config MMCSS start= auto ; sc.exe start MMCSS, then RE-CHECK. Measured: after a graphics driver install this failed many times in a row (first "failed 2: file not found" although mmcss.sys is present and validly signed, then 1341 "the server is currently disabled" even across a reboot) and STILL came up later on a retry - so retry rather than concluding it is broken' })
