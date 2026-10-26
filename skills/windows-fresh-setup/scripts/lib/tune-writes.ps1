# Tune write list - the single source of truth for what the tune phase changes.
#
# setup.ps1 dot-sources this file and applies $TuneWrites; check-tune-consistency.ps1 reads it
# through the AST and compares it with the acceptance checks in verify-env.ps1, so a write
# cannot be added without a check (or a check left behind after a write is removed).
# Docs quote these counts; scripts/check-counts.ps1 enforces them.
#
# Keep this file ASCII-only: it is loaded on Windows PowerShell 5.1 as well, which decodes a
# BOM-less file as ANSI.

        $TuneWrites = @(
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Value = 0; Type = 'DWord';
               Why = 'GameDVR background recording costs frames' }
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0; Type = 'DWord';
               Why = 'same switch, user scope' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Value = 10; Type = 'DWord';
               Why = 'MMCSS: give the game thread more CPU (default 20)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Value = 0xffffffff; Type = 'DWord';
               Why = 'MMCSS: no network throttling while gaming' }
            # The Games task class. verify-env.ps1 checks GPU Priority and Scheduling
            # Category, so they have to be written here or those two checks fail on every
            # single machine - the two halves of the project have to agree.
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Value = 8; Type = 'DWord';
               Why = 'MMCSS: game task GPU priority (verify-env checks this)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Value = 6; Type = 'DWord';
               Why = 'MMCSS: game task CPU priority' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Value = 'High'; Type = 'String';
               Why = 'MMCSS: game task scheduling category (verify-env checks this)' }
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Value = 'High'; Type = 'String';
               Why = 'MMCSS: game task storage IO priority' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord';
               Why = 'stop silent app installs / promoted apps' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = $telemetryMax; Type = 'DWord';
               Why = "telemetry at the strictest level this SKU honours ($edition -> $telemetryMax)" }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no silent Store installs' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord'; Why = 'no Start menu suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Value = 0; Type = 'DWord'; Why = 'no Start recommendations' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Value = 0; Type = 'DWord'; Why = 'no Windows welcome suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Value = 0; Type = 'DWord'; Why = 'no Timeline suggestions' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Value = 0; Type = 'DWord'; Why = 'no Windows tips popups' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Value = 0; Type = 'DWord'; Why = 'no lock-screen ads' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'PreInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no preinstalled app promotion' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'OemPreInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Why = 'no OEM app promotion' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = 0; Type = 'DWord'; Why = 'no "sync your settings" ads in Explorer' }
            # Start-menu web search. The obvious key (`...\CurrentVersion\Search`:
            # BingSearchEnabled / CortanaConsent) is NOT reliably writable: measured on
            # Windows 11 24H2+, writes there are refused at kernel level with "Not all data
            # was successfully written to the registry" while the key's ACL still shows the
            # user FullControl - so it is not an ACL problem and cannot be fixed by taking
            # ownership. The policy keys below are the official route and were verified to
            # accept the write. Policy also outranks the user-scope value, so this is not a
            # downgrade. verify-env.ps1 accepts EITHER route.
            @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Value = 1; Type = 'DWord'; Why = 'Start search stops offering web suggestions' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Value = 0; Type = 'DWord'; Why = 'no web results in Start search (machine policy)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Value = 0; Type = 'DWord'; Why = 'no cloud search consent' }

            # --- safety nets, not perf -------------------------------------------------
            # These three come from Sophia-Script / Bloatynosy and are the "make the machine
            # recoverable" half of the tune phase. Each was measured absent on a real machine.
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'EnablePeriodicBackup'; Value = 1; Type = 'DWord';
               Why = 'attempt periodic registry hive backup; MEASURED no-op on Win11 26xxx (empty RegIdleBackup, SIT gone) - the restore point is the real undo' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'; Name = 'PreventDeviceEncryption'; Value = 1; Type = 'DWord';
               Why = 'block FUTURE automatic device encryption; never touches volumes that are already encrypted' }

            # --- network politeness -----------------------------------------------------
            @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'; Name = 'DODownloadMode'; Value = 1; Type = 'DWord';
               Why = 'update delivery stays on the LAN instead of uploading to the internet' }

            # --- disk housekeeping ------------------------------------------------------
            # Storage Sense is on by default but only for temp files. Recycle-bin cleanup is
            # opt-in. The downloads rule is deliberately NOT enabled: auto-deleting files from
            # the Downloads folder can eat a user's installer, and the saving is trivial.
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '08'; Value = 1; Type = 'DWord';
               Why = 'Storage Sense empties the recycle bin' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '32'; Value = 30; Type = 'DWord';
               Why = 'recycle bin retention: 30 days' }            # --- attack surface & device hygiene (from winutil / Winhance, verified in their source) ---
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'DisableWpbtExecution'; Value = 1; Type = 'DWord';
               Why = 'blocks OEM firmware-injected executables at boot (WPBT); nothing legitimate on this machine uses it' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'; Name = 'PreventDeviceMetadataFromNetwork'; Value = 1; Type = 'DWord';
               Why = 'stops "install this app" payloads when a monitor/printer is plugged in' }
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'; Name = 'BackupCount'; Value = 2; Type = 'DWord';
               Why = 'keeps two generations of registry hive backups instead of one (only meaningful together with EnablePeriodicBackup)' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Value = 1; Type = 'DWord';
               Why = 'Store apps cannot run in the background; foreground use is unaffected' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Value = 0; Type = 'DWord';
               Why = 'no "what is new after the update" splash; distinct from the 338388/338389/353698 campaign IDs' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'; Name = 'LockScreenToastEnabled'; Value = 0; Type = 'DWord';
               Why = 'no notification content on the lock screen' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name = 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK'; Value = 0; Type = 'DWord';
               Why = 'same switch, per-user notification setting scope' }            # --- privacy surfaces (from Win11Debloat / Sophia / Bloatynosy, paths read in their .reg files) ---
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0; Type = 'DWord';
               Why = 'removes the per-user advertising ID used to correlate apps' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0; Type = 'DWord';
               Why = 'no personalised tips derived from diagnostic data' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0; Type = 'DWord';
               Why = 'no timeline activity upload (policy scope)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Value = 0; Type = 'DWord';
               Why = 'timeline feed off; same policy family as PublishUserActivities' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'AllowInputPersonalization'; Value = 0; Type = 'DWord';
               Why = 'typing/inking data is not sent for personalisation' }
            @{ Path = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Value = 0; Type = 'DWord';
               Why = 'cloud speech recognition consent withdrawn (local speech still works)' }
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Value = 0; Type = 'DWord';
               Why = 'Edge stops keeping preloaded processes resident after boot; first launch is slower' }            # --- shell & device behaviour (Winhance GamingAndPerformance / Taskbar / Explorer, read in source) ---
            @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Type = 'DWord';
               Why = 'Game Mode on: Windows suppresses background work and keeps game threads scheduled; default is already 1, this pins it' }
            # MEASURED: the Dsh (Widgets) policy keys are ACL-locked on this machine - owner is
            # BUILTIN\Administrators but the interactive user holds ReadKey only, and both
            # `reg add HKCU\...\Dsh` and `reg add HKLM\...\Dsh` return "Access is denied" even
            # from an elevated prompt (a security product likely guards the path). A write that
            # cannot land must not be attempted and then reported as a tweak - it is documented
            # under the manual-items section of docs/03-system-tweaks.md instead.
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowCloudFilesInQuickAccess'; Value = 0; Type = 'DWord';
               Why = 'Quick Access stops querying Office.com cloud files (clutter + a cloud call on every Explorer open)' }
            @{ Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'LegacyDefaultPrinterMode'; Value = 1; Type = 'DWord';
               Why = 'Windows stops silently switching the default printer to the "last used" one' }
        )