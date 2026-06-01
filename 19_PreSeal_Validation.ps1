#Requires -Version 7.0
<#
.SYNOPSIS  Section 19 — Pre-Seal Validation (Golden Image Sealing Readiness Check)

.DESCRIPTION
    Comprehensive GO / NO-GO check before snapshotting / sealing the golden image.
    Verifies that the image is clean, fully configured, and ready for production use.

    Checks performed:
      1. No temp user profiles exist under C:\Users\ (except Default, Public, Administrator)
      2. Windows event logs cleared (Application, System, Security, Setup)
      3. Temp directories empty (C:\Windows\Temp, C:\Temp, %TEMP%)
      4. C:\VDI_GPO_Logs\ exists and all 17 section logs are present
      5. All critical VDI services in correct startup state
      6. Machine password rotation disabled (DisablePasswordChange=1)
      7. No pending Windows Update reboot flag
      8. FSLogix Profile Container disabled, ODFC enabled
      9. Horizon Agent service present and Automatic
     10. No orphaned AppData from build-time installs in C:\Users\Default
     11. CAC/Smart Card service (SCardSvr) Automatic
     12. DEM FlexEngine service detected and Automatic
     13. DoD Root CA certificates present (at least one)
     14. SMBv1 disabled
     15. High Performance power plan active
     16. Screen saver suppressed
     17. Windows Hello for Business disabled (conflicts with CAC)
     18. Hibernation disabled
     19. AllowTelemetry policy set (not missing)
     20. Windows Search / SysMain disabled (VDI best practice)

    Output: GO (all critical checks pass) or NO-GO (one or more critical checks failed)
    with per-check detail and remediation hints.

.PARAMETER StrictMode
    If specified, treats WARN-level findings as NO-GO blockers. Default: $false (WARN
    is advisory only — GO verdict still possible with warnings).

.PARAMETER LogPath
    Path to write the pre-seal validation log.
    Default: C:\VDI_GPO_Logs\19_PreSeal_Validation_<timestamp>.log

.EXAMPLE
    # Standard pre-seal check (recommended)
    .\19_PreSeal_Validation.ps1

    # Strict mode — any warning is a blocker
    .\19_PreSeal_Validation.ps1 -StrictMode

.NOTES
    Run As : Local Administrator / SYSTEM
    Run    : Immediately before snapshotting / sealing the golden image.
             After all Build scripts (00_Master_RunAll.ps1) have completed.
#>

[CmdletBinding()]
param(
    [switch]$StrictMode,
    [string]$LogPath = "C:\VDI_GPO_Logs\19_PreSeal_Validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Logging ────────────────────────────────────────────────────────────────────
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$($Level.PadRight(5))] $Msg"
    $col  = switch ($Level) {
        "PASS"  { "Green"   }
        "FAIL"  { "Red"     }
        "WARN"  { "Yellow"  }
        "SKIP"  { "Gray"    }
        default { "White"   }
    }
    Write-Host $line -ForegroundColor $col
    Add-Content -Path $LogPath -Value $line
}

# ── Check tracking ─────────────────────────────────────────────────────────────
$checkPass = 0; $checkFail = 0; $checkWarn = 0

function Add-Check {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL","WARN","SKIP")][string]$Status,
        [string]$Detail = "",
        [string]$Fix    = "",
        [switch]$Critical   # FAIL on critical = NO-GO regardless of StrictMode
    )
    switch ($Status) {
        "PASS" { $script:checkPass++ }
        "FAIL" { $script:checkFail++ }
        "WARN" { $script:checkWarn++ }
    }
    $icon = switch ($Status) { "PASS"{"✓"} "FAIL"{"✗"} "WARN"{"⚠"} default{"–"} }
    Write-Log "$icon  $Name" $Status
    if ($Detail) { Write-Log "     Detail : $Detail" "INFO" }
    if ($Fix -and $Status -in "FAIL","WARN") { Write-Log "     Fix    : $Fix" "INFO" }
}

# ── Admin guard ────────────────────────────────────────────────────────────────
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must run as Administrator." -ForegroundColor Red
    exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
Write-Log "================================================================================" "INFO"
Write-Log "  OMNISSA HORIZON VDI — GOLDEN IMAGE PRE-SEAL VALIDATION" "INFO"
Write-Log "  Host : $($env:COMPUTERNAME)   |   Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
Write-Log "  Mode : $(if ($StrictMode) {'STRICT (WARNs treated as failures)'} else {'STANDARD (WARNs are advisory)'})" "INFO"
Write-Log "================================================================================" "INFO"
Write-Log ""

# ── CHECK 1: No temp user profiles ────────────────────────────────────────────
Write-Log "--- 1. Stale user profiles under C:\Users\" "INFO"
$allowedProfiles = @("Default", "Default User", "Public", "Administrator", "All Users", "defaultuser0")
$userDirs = Get-ChildItem "C:\Users\" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin $allowedProfiles }

if ($userDirs.Count -eq 0) {
    Add-Check "No stale user profiles" "PASS"
} else {
    $names = ($userDirs | Select-Object -ExpandProperty Name) -join ", "
    Add-Check "No stale user profiles" "FAIL" `
        -Detail "Found: $names" `
        -Fix "Remove build-time user profiles: $names from C:\Users\ before sealing." `
        -Critical
}

# ── CHECK 2: Event logs cleared ───────────────────────────────────────────────
Write-Log "--- 2. Windows event logs cleared" "INFO"
$logNames = @("Application", "System", "Security", "Setup")
$dirtyLogs = @()
foreach ($ln in $logNames) {
    try {
        $count = (Get-WinEvent -LogName $ln -MaxEvents 1 -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($count -gt 0) { $dirtyLogs += $ln }
    } catch { }
}
if ($dirtyLogs.Count -eq 0) {
    Add-Check "Event logs cleared" "PASS"
} else {
    Add-Check "Event logs cleared" "WARN" `
        -Detail "Logs with events: $($dirtyLogs -join ', ')" `
        -Fix "Clear logs: wevtutil cl Application; wevtutil cl System; wevtutil cl Security; wevtutil cl Setup"
}

# ── CHECK 3: Temp directories empty ───────────────────────────────────────────
Write-Log "--- 3. Temp directories empty" "INFO"
$tempDirs = @("C:\Windows\Temp", "C:\Temp")
$dirtyTemps = @()
foreach ($td in $tempDirs) {
    if (Test-Path $td) {
        $count = (Get-ChildItem $td -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($count -gt 0) { $dirtyTemps += "$td ($count items)" }
    }
}
if ($dirtyTemps.Count -eq 0) {
    Add-Check "Temp directories empty" "PASS"
} else {
    Add-Check "Temp directories empty" "WARN" `
        -Detail "Non-empty: $($dirtyTemps -join '; ')" `
        -Fix "Run: Remove-Item C:\Windows\Temp\* -Recurse -Force; Remove-Item C:\Temp\* -Recurse -Force"
}

# ── CHECK 4: All 17 section logs present ──────────────────────────────────────
Write-Log "--- 4. Build script log files" "INFO"
$logDirPath = "C:\VDI_GPO_Logs"
if (-not (Test-Path $logDirPath)) {
    Add-Check "Build log directory exists" "FAIL" `
        -Detail "$logDirPath not found" `
        -Fix "Run 00_Master_RunAll.ps1 before sealing." `
        -Critical
} else {
    $expectedLogs = @(
        "01_FirstRun_WelcomeSuppression.log", "02_Logon_Speed_Animation.log",
        "03_Microsoft_Teams.log", "04_OneDrive_ForBusiness.log",
        "05_FSLogix_OfficeContainer.log", "06_DEM_ProfileManagement.log",
        "07_StartMenu_Taskbar.log", "08_Search_Cortana_AI.log",
        "09_Privacy_Telemetry.log", "10_Notifications_ActionCenter.log",
        "11_WindowsUpdate_Patching.log", "12_Security_Defender.log",
        "13_Horizon_Specific.log", "14_Power_Performance.log",
        "15_Services.log", "16_Network_OfflineFiles.log", "17_SmartCard_CAC_Login.log"
    )
    $missingLogs = $expectedLogs | Where-Object { -not (Test-Path (Join-Path $logDirPath $_)) }
    if ($missingLogs.Count -eq 0) {
        Add-Check "All 17 section logs present" "PASS"
    } else {
        Add-Check "All 17 section logs present" "FAIL" `
            -Detail "Missing logs: $($missingLogs -join ', ')" `
            -Fix "Re-run missing sections or run 00_Master_RunAll.ps1 to generate all logs." `
            -Critical
    }
}

# ── CHECK 5: Critical service startup states ───────────────────────────────────
Write-Log "--- 5. Critical VDI service startup states" "INFO"
$svcChecks = @(
    @{ Name="SCardSvr";    Expect="Automatic"; Label="Smart Card (SCardSvr)";     Critical=$true  },
    @{ Name="ScDeviceEnum";Expect="Automatic"; Label="Smart Card Device Enum";    Critical=$false },
    @{ Name="NlaSvc";      Expect="Automatic"; Label="Network Location Aware";    Critical=$true  },
    @{ Name="Netlogon";    Expect="Automatic"; Label="Netlogon";                  Critical=$true  },
    @{ Name="frxsvc";      Expect="Automatic"; Label="FSLogix (frxsvc)";          Critical=$false },
    @{ Name="SysMain";     Expect="Disabled";  Label="SysMain (Superfetch)";      Critical=$false },
    @{ Name="WSearch";     Expect="Disabled";  Label="Windows Search (WSearch)";  Critical=$false },
    @{ Name="XblAuthManager"; Expect="Disabled"; Label="Xbox Auth Manager";       Critical=$false }
)
foreach ($sc in $svcChecks) {
    $svc = Get-Service -Name $sc.Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        if ($sc.Critical) {
            Add-Check "$($sc.Label) service" "FAIL" -Detail "Service not found" `
                -Fix "Install the required component." -Critical
        } else {
            Add-Check "$($sc.Label) service" "SKIP" -Detail "Not installed — skipping."
        }
    } else {
        if ($svc.StartType -eq $sc.Expect) {
            Add-Check "$($sc.Label): $($sc.Expect)" "PASS"
        } else {
            $severity = if ($sc.Critical) { "FAIL" } else { "WARN" }
            Add-Check "$($sc.Label): $($sc.Expect)" $severity `
                -Detail "Actual: $($svc.StartType)" `
                -Fix "Set-Service -Name $($sc.Name) -StartupType $($sc.Expect)"
        }
    }
}

# DEM service — auto-detect
$demSvc = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*DEM*" -or $_.DisplayName -like "*Dynamic Environment*" -or $_.DisplayName -like "*FlexEngine*" } |
    Select-Object -First 1
if ($null -ne $demSvc) {
    if ($demSvc.StartType -eq "Automatic") {
        Add-Check "DEM FlexEngine ($($demSvc.Name)): Automatic" "PASS"
    } else {
        Add-Check "DEM FlexEngine ($($demSvc.Name)): Automatic" "WARN" `
            -Detail "Actual: $($demSvc.StartType)" `
            -Fix "Set-Service -Name $($demSvc.Name) -StartupType Automatic"
    }
} else {
    Add-Check "DEM FlexEngine service" "WARN" `
        -Detail "Not found — DEM agent may not be installed" `
        -Fix "Install Omnissa DEM agent on the golden image before sealing."
}

# Horizon Agent service
$horizonSvc = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "vmware-viewagent*" -or $_.Name -like "horizon*agent*" -or $_.DisplayName -like "*Horizon*Agent*" } |
    Select-Object -First 1
if ($null -ne $horizonSvc) {
    if ($horizonSvc.StartType -eq "Automatic") {
        Add-Check "Horizon Agent ($($horizonSvc.Name)): Automatic" "PASS"
    } else {
        Add-Check "Horizon Agent ($($horizonSvc.Name)): Automatic" "FAIL" `
            -Detail "Actual: $($horizonSvc.StartType)" `
            -Fix "Set-Service -Name $($horizonSvc.Name) -StartupType Automatic" `
            -Critical
    }
} else {
    Add-Check "Horizon Agent service" "FAIL" `
        -Detail "Not found — Horizon Agent must be installed before sealing" `
        -Fix "Install Omnissa Horizon Agent on the golden image." `
        -Critical
}

# ── CHECK 6: Machine password rotation disabled ────────────────────────────────
Write-Log "--- 6. Machine password rotation (non-persistent clone safety)" "INFO"
$pwChange = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
    -Name "DisablePasswordChange" -ErrorAction SilentlyContinue).DisablePasswordChange
if ($pwChange -eq 1) {
    Add-Check "Machine password rotation disabled (DisablePasswordChange=1)" "PASS"
} else {
    Add-Check "Machine password rotation disabled (DisablePasswordChange=1)" "FAIL" `
        -Detail "Current value: $pwChange (or not set)" `
        -Fix "Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -Name DisablePasswordChange -Value 1" `
        -Critical
}

# ── CHECK 7: No pending Windows Update reboot ─────────────────────────────────
Write-Log "--- 7. Pending Windows Update reboot flag" "INFO"
$wuReboot1 = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$wuReboot2 = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
$cbsReboot  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing" `
    -Name "RebootPending" -ErrorAction SilentlyContinue).RebootPending
if (-not ($wuReboot1 -or $wuReboot2 -or $cbsReboot)) {
    Add-Check "No pending Windows Update reboot" "PASS"
} else {
    Add-Check "No pending Windows Update reboot" "FAIL" `
        -Detail "Reboot pending — image state is incomplete until rebooted" `
        -Fix "Reboot the golden image VM before sealing." `
        -Critical
}

# ── CHECK 8: FSLogix ODFC enabled, Profile Container disabled ─────────────────
Write-Log "--- 8. FSLogix ODFC enabled / Profile Container disabled" "INFO"
$odfcEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\FSLogix\ODFC" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
if (-not $odfcEnabled) {
    $odfcEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
}
$profileEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled

if ($odfcEnabled -eq 1) {
    Add-Check "FSLogix ODFC Enabled = 1" "PASS"
} else {
    Add-Check "FSLogix ODFC Enabled = 1" "FAIL" `
        -Detail "ODFC is not enabled (value: $odfcEnabled)" `
        -Fix "Run 05_FSLogix_OfficeContainer.ps1 or set HKLM:\SOFTWARE\FSLogix\ODFC\Enabled = 1" `
        -Critical
}
if ($profileEnabled -eq 0 -or $null -eq $profileEnabled) {
    Add-Check "FSLogix Profile Container Disabled (DEM owns profile)" "PASS"
} else {
    Add-Check "FSLogix Profile Container Disabled (DEM owns profile)" "FAIL" `
        -Detail "Profile Container is ENABLED — this conflicts with DEM" `
        -Fix "Set HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 0" `
        -Critical
}

# ── CHECK 9: Orphaned AppData in Default profile ───────────────────────────────
Write-Log "--- 9. Orphaned AppData in Default user profile" "INFO"
$defaultAppData = "C:\Users\Default\AppData\Local"
if (Test-Path $defaultAppData) {
    $appDataItems = Get-ChildItem $defaultAppData -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @("Microsoft", "Temp") }
    if ($appDataItems.Count -eq 0) {
        Add-Check "Default user AppData is clean" "PASS"
    } else {
        $names = ($appDataItems | Select-Object -ExpandProperty Name) -join ", "
        Add-Check "Default user AppData is clean" "WARN" `
            -Detail "Non-standard folders: $names" `
            -Fix "Remove unexpected folders from C:\Users\Default\AppData\Local\ before sealing."
    }
}

# ── CHECK 10: DoD Root CA certificates ────────────────────────────────────────
Write-Log "--- 10. DoD Root CA certificates in LocalMachine store" "INFO"
try {
    $dodCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop |
        Where-Object { $_.Subject -match "DoD|Department of Defense" }
    if ($dodCerts.Count -gt 0) {
        Add-Check "DoD Root CA certificates present ($($dodCerts.Count) found)" "PASS"
    } else {
        Add-Check "DoD Root CA certificates present" "FAIL" `
            -Detail "No DoD Root CA certs in LocalMachine\Root" `
            -Fix "Run DISA InstallRoot.exe /S to install DoD PKI trust chain." `
            -Critical
    }
} catch {
    Add-Check "DoD Root CA certificate check" "WARN" `
        -Detail "Could not read certificate store: $_" `
        -Fix "Run as Administrator and retry."
}

# ── CHECK 11: SMBv1 disabled ──────────────────────────────────────────────────
Write-Log "--- 11. SMBv1 protocol disabled" "INFO"
$smb1 = Get-WindowsOptionalFeature -FeatureName SMB1Protocol -Online -ErrorAction SilentlyContinue
if ($smb1.State -eq "Disabled") {
    Add-Check "SMBv1 disabled" "PASS"
} else {
    Add-Check "SMBv1 disabled" "FAIL" `
        -Detail "SMBv1 is $($smb1.State)" `
        -Fix "Disable-WindowsOptionalFeature -FeatureName SMB1Protocol -Online -NoRestart" `
        -Critical
}

# ── CHECK 12: High Performance power plan ─────────────────────────────────────
Write-Log "--- 12. Power plan active" "INFO"
$activePlan = & powercfg /getactivescheme 2>&1
if ($activePlan -match "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|High performance") {
    Add-Check "High Performance power plan active" "PASS"
} else {
    Add-Check "High Performance power plan active" "WARN" `
        -Detail "Active plan: $activePlan" `
        -Fix "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
}

# ── CHECK 13: Hibernation disabled ────────────────────────────────────────────
Write-Log "--- 13. Hibernation disabled" "INFO"
$hibEnabled = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" `
    -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
if ($hibEnabled -eq 0) {
    Add-Check "Hibernation disabled" "PASS"
} else {
    Add-Check "Hibernation disabled" "WARN" `
        -Detail "HibernateEnabled = $hibEnabled" `
        -Fix "powercfg /h off"
}

# ── CHECK 14: Screen saver suppressed ─────────────────────────────────────────
Write-Log "--- 14. Screen saver suppressed" "INFO"
$ssActive = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -Name ScreenSaveActive -ErrorAction SilentlyContinue).ScreenSaveActive
if ($ssActive -eq "0" -or $ssActive -eq 0) {
    Add-Check "Screen saver suppressed (ScreenSaveActive=0)" "PASS"
} else {
    Add-Check "Screen saver suppressed (ScreenSaveActive=0)" "WARN" `
        -Detail "ScreenSaveActive = $ssActive" `
        -Fix "Run 13_Horizon_Specific.ps1 or set HKLM policy ScreenSaveActive = '0'"
}

# ── CHECK 15: Windows Hello for Business disabled ─────────────────────────────
Write-Log "--- 15. Windows Hello for Business disabled (CAC environment)" "INFO"
$helloEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork" `
    -Name Enabled -ErrorAction SilentlyContinue).Enabled
if ($helloEnabled -eq 0) {
    Add-Check "Windows Hello for Business disabled (conflicts with CAC)" "PASS"
} else {
    Add-Check "Windows Hello for Business disabled (conflicts with CAC)" "WARN" `
        -Detail "PassportForWork\Enabled = $helloEnabled (should be 0)" `
        -Fix "Run 17_SmartCard_CAC_Login.ps1 or set HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork\Enabled = 0"
}

# ── CHECK 16: Telemetry policy set ────────────────────────────────────────────
Write-Log "--- 16. Telemetry policy configured" "INFO"
$telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
if ($null -ne $telemetry) {
    Add-Check "AllowTelemetry policy set (value: $telemetry)" "PASS"
} else {
    Add-Check "AllowTelemetry policy configured" "WARN" `
        -Detail "AllowTelemetry not set under Policies path" `
        -Fix "Run 09_Privacy_Telemetry.ps1"
}

# ── CHECK 17: OneDrive Silent Sign-In ─────────────────────────────────────────
Write-Log "--- 17. OneDrive Silent Account Config (SSO)" "INFO"
$odSilent = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name SilentAccountConfig -ErrorAction SilentlyContinue).SilentAccountConfig
if ($odSilent -eq 1) {
    Add-Check "OneDrive SilentAccountConfig = 1 (SSO on logon)" "PASS"
} else {
    Add-Check "OneDrive SilentAccountConfig = 1 (SSO on logon)" "WARN" `
        -Detail "SilentAccountConfig = $odSilent" `
        -Fix "Run 04_OneDrive_ForBusiness.ps1"
}

# ── CHECK 18: Horizon True SSO registry ───────────────────────────────────────
Write-Log "--- 18. Horizon True SSO registry entries" "INFO"
$tssoEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\VMware, Inc.\VMware VDM\Agent\Configuration" `
    -Name "TrueSSO" -ErrorAction SilentlyContinue).TrueSSO
if ($tssoEnabled -eq 1) {
    Add-Check "Horizon True SSO enabled (TrueSSO=1)" "PASS"
} else {
    Add-Check "Horizon True SSO enabled (TrueSSO=1)" "WARN" `
        -Detail "TrueSSO = $tssoEnabled — Horizon True SSO agent-side key not set" `
        -Fix "Run 17_SmartCard_CAC_Login.ps1"
}

# ── CHECK 19: Windows Recall disabled (24H2) ──────────────────────────────────
Write-Log "--- 19. Windows Recall / AI features disabled" "INFO"
$recallEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" `
    -Name "AllowRecall" -ErrorAction SilentlyContinue).AllowRecall
if ($recallEnabled -eq 0) {
    Add-Check "Windows Recall disabled (AllowRecall=0)" "PASS"
} else {
    Add-Check "Windows Recall disabled" "WARN" `
        -Detail "AllowRecall = $recallEnabled (should be 0 on VDI)" `
        -Fix "Run 08_Search_Cortana_AI.ps1"
}

# ── CHECK 20: Teams auto-update disabled ──────────────────────────────────────
Write-Log "--- 20. Teams auto-update disabled (golden image controls versioning)" "INFO"
$teamsUpdate = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Teams" `
    -Name "DisableAutoUpdate" -ErrorAction SilentlyContinue).DisableAutoUpdate
if ($teamsUpdate -eq 1) {
    Add-Check "Teams auto-update disabled" "PASS"
} else {
    Add-Check "Teams auto-update disabled" "WARN" `
        -Detail "DisableAutoUpdate = $teamsUpdate" `
        -Fix "Run 03_Microsoft_Teams.ps1"
}

# ══════════════════════════════════════════════════════════════════════════════
# VERDICT
# ══════════════════════════════════════════════════════════════════════════════
Write-Log "" "INFO"
Write-Log "================================================================================" "INFO"
Write-Log "  PRE-SEAL VALIDATION SUMMARY" "INFO"
Write-Log "  ✓ PASS : $checkPass" "PASS"
Write-Log "  ✗ FAIL : $checkFail" $(if ($checkFail -gt 0) { "FAIL" } else { "INFO" })
Write-Log "  ⚠ WARN : $checkWarn" $(if ($checkWarn -gt 0) { "WARN" } else { "INFO" })
Write-Log "" "INFO"

$isNoGo = $checkFail -gt 0 -or ($StrictMode -and $checkWarn -gt 0)

if ($isNoGo) {
    $reason = if ($checkFail -gt 0) { "$checkFail critical check(s) failed" } else { "$checkWarn warning(s) in strict mode" }
    Write-Log "  VERDICT: *** NO-GO *** ($reason)" "FAIL"
    Write-Log "  Resolve the issues above before sealing the golden image." "FAIL"
    Write-Log "================================================================================" "INFO"
    Write-Log "Log: $LogPath" "INFO"
    exit 1
} else {
    if ($checkWarn -gt 0) {
        Write-Log "  VERDICT: GO  (with $checkWarn advisory warning(s) — review before sealing)" "WARN"
    } else {
        Write-Log "  VERDICT: *** GO *** — All checks passed. Image is ready to seal." "PASS"
    }
    Write-Log "" "INFO"
    Write-Log "  NEXT STEPS:" "INFO"
    Write-Log "    1. Optionally run IMAGE.COMPLIANCE\files\VDI_GoldenImage_Compliance_Audit.ps1" "INFO"
    Write-Log "    2. Shut down the VM" "INFO"
    Write-Log "    3. Take snapshot / seal the golden image in Horizon Console" "INFO"
    Write-Log "    4. Assign the image to a pool and test CAC logon before full deployment" "INFO"
    Write-Log "================================================================================" "INFO"
    Write-Log "Log: $LogPath" "INFO"
    exit 0
}
