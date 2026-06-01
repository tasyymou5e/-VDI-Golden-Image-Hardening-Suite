#Requires -Version 7.0
<#
.SYNOPSIS  Section 14 — Power & Performance
.NOTES
    Log : C:\VDI_GPO_Logs\14_Power_Performance.log
    Sets High Performance power plan, disables hibernate/sleep,
    USB selective suspend, hard disk timeout.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "14_Power_Performance"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Power and Performance settings ===" "INFO"

$hpGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# ── 1. Set High Performance power plan ───────────────────────────────────────
Write-Log "--- 1. Activate High Performance power plan" "INFO"
try {
    & powercfg /setactive $hpGuid 2>&1 | Out-Null
    $active = (& powercfg /getactivescheme) -match $hpGuid
    if ($active) { Write-Log "High Performance plan active." "SUCCESS" }
    else { Write-Log "Could not confirm High Performance plan active — check powercfg output." "WARN"; $warns++ }
} catch { Write-Log "powercfg failed: $_" "ERROR"; $errors++ }

# ── 2. Disable Hibernate ─────────────────────────────────────────────────────
Write-Log "--- 2. Disable Hibernate" "INFO"
try { & powercfg /h off 2>&1 | Out-Null; Write-Log "Hibernate disabled." "SUCCESS" }
catch { Write-Log "Hibernate disable failed: $_" "WARN"; $warns++ }

# ── 3. Disable sleep / standby (AC) ──────────────────────────────────────────
Write-Log "--- 3. Disable sleep/standby timeouts (AC power)" "INFO"
try {
    & powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
    & powercfg /change standby-timeout-dc 0 2>&1 | Out-Null
    & powercfg /change monitor-timeout-ac 0 2>&1 | Out-Null
    Write-Log "Sleep/standby timeouts set to never." "SUCCESS"
} catch { Write-Log "Failed to set sleep timeouts: $_" "WARN"; $warns++ }

# ── 4. Disable hard disk turn-off ────────────────────────────────────────────
Write-Log "--- 4. Disable hard disk power-off timeout" "INFO"
try {
    & powercfg /change disk-timeout-ac 0 2>&1 | Out-Null
    & powercfg /change disk-timeout-dc 0 2>&1 | Out-Null
    Write-Log "Disk timeout set to never." "SUCCESS"
} catch { Write-Log "Failed to set disk timeout: $_" "WARN"; $warns++ }

# ── 5. Disable USB selective suspend ─────────────────────────────────────────
Write-Log "--- 5. Disable USB selective suspend (prevents CAC/PIV reader dropout)" "INFO"
$usbSubGroup = "2a737441-1930-4402-8d77-b2bebba308a3"
$usbSetting  = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
try {
    & powercfg /setacvalueindex SCHEME_CURRENT $usbSubGroup $usbSetting 0 2>&1 | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT $usbSubGroup $usbSetting 0 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    Write-Log "USB selective suspend disabled." "SUCCESS"
} catch { Write-Log "USB selective suspend config failed: $_" "WARN"; $warns++ }

# ── 6. Set processor min/max performance state ────────────────────────────────
Write-Log "--- 6. Set processor performance state to 100% min/max" "INFO"
$cpuSubGroup = "54533251-82be-4824-96c1-47b60b740d00"
$minState    = "893dee8e-2bef-41e0-89c6-b55d0929964c"
$maxState    = "bc5038f7-23e0-4960-96da-33abaf5935ec"
try {
    & powercfg /setacvalueindex SCHEME_CURRENT $cpuSubGroup $minState 100 2>&1 | Out-Null
    & powercfg /setacvalueindex SCHEME_CURRENT $cpuSubGroup $maxState 100 2>&1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    Write-Log "CPU performance state set to 100% min/max." "SUCCESS"
} catch { Write-Log "CPU performance state config failed: $_" "WARN"; $warns++ }

Write-Log "=== Section 14 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
