#Requires -Version 7.0
<#
.SYNOPSIS  Section 15 — Windows Services Optimisation for VDI
.NOTES
    Log : C:\VDI_GPO_Logs\15_Services.log
    Disables services that waste resources or cause issues on non-persistent
    Horizon VDI sessions. Sets critical VDI services to Automatic.

    CONFIG FLAGS (set at top of file):
      $disableWindowsSearch  — set $true if Search indexing not needed (recommended)
      $disablePrintSpooler   — set $true if Horizon Virtual Printing is not required

    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "15_Services"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG ─────────────────────────────────────────────────────────────────────
$disableWindowsSearch = $true   # Recommended: indexing is counterproductive on non-persistent VDI
$disablePrintSpooler  = $false  # Set $true if Horizon Virtual Printing is NOT used
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring Windows Services for VDI optimisation ===" "INFO"

# ── SERVICES TO DISABLE ────────────────────────────────────────────────────────

# ── 1. Xbox / Gaming services (no place in enterprise VDI) ────────────────────
Write-Log "--- 1. Disable Xbox/Gaming services" "INFO"
$xboxServices = @("XblAuthManager","XblGameSave","XboxNetApiSvc","XboxGipSvc")
foreach ($svc in $xboxServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $s) {
        if (-not (Set-ServiceConfig -Name $svc -StartupType Disabled -StopNow $true)) { $warns++ }
    } else {
        Write-Log "SKIP: $svc not present on this image." "SKIP"; $skipped++
    }
}

# ── 2. SysMain (Superfetch / Prefetch) ────────────────────────────────────────
# Counterproductive on non-persistent VDI: disk cache is cold every session
Write-Log "--- 2. Disable SysMain (Superfetch/Prefetch)" "INFO"
if (-not (Set-ServiceConfig -Name "SysMain" -StartupType Disabled -StopNow $true)) { $warns++ }

# ── 3. Windows Error Reporting ────────────────────────────────────────────────
# Excessive disk I/O during VDI sessions; reports are lost on session teardown
Write-Log "--- 3. Disable Windows Error Reporting service" "INFO"
if (-not (Set-ServiceConfig -Name "WerSvc" -StartupType Disabled -StopNow $true)) { $warns++ }

# ── 4. Diagnostic Policy Service (DPS) ───────────────────────────────────────
# Runs troubleshooting wizards — unnecessary in managed VDI environment
Write-Log "--- 4. Disable Diagnostic Policy Service" "INFO"
if (-not (Set-ServiceConfig -Name "DPS" -StartupType Disabled -StopNow $true)) { $warns++ }

# ── 5. Windows Update Medic Service ───────────────────────────────────────────
# WaaSMedicSvc tries to re-enable Windows Update even when disabled via GPO
Write-Log "--- 5. Disable Windows Update Medic Service (WaaSMedicSvc)" "INFO"
try {
    # This service is protected; must use registry to disable
    Set-RegValue -Hive HKLM `
        -Path "SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" `
        -Name "Start" -Value 4 | Out-Null  # 4 = Disabled
    Write-Log "WaaSMedicSvc disabled via registry (protected service)." "SUCCESS"
} catch {
    Write-Log "WaaSMedicSvc disable failed (may be OS-protected): $_" "WARN"; $warns++
}

# ── 6. Windows Search (conditional) ──────────────────────────────────────────
Write-Log "--- 6. Windows Search service (WSearch) — conditional" "INFO"
if ($disableWindowsSearch) {
    if (-not (Set-ServiceConfig -Name "WSearch" -StartupType Disabled -StopNow $true)) { $warns++ }
    Write-Log "Windows Search disabled. Outlook Search Indexing will use online mode." "WARN"; $warns++
} else {
    Write-Log "SKIP: Windows Search not disabled (disableWindowsSearch = false)." "SKIP"; $skipped++
}

# ── 7. Print Spooler (conditional) ───────────────────────────────────────────
Write-Log "--- 7. Print Spooler (Spooler) — conditional" "INFO"
if ($disablePrintSpooler) {
    if (-not (Set-ServiceConfig -Name "Spooler" -StartupType Disabled -StopNow $true)) { $warns++ }
    Write-Log "Print Spooler disabled. Horizon Virtual Printing will NOT function." "WARN"; $warns++
} else {
    Write-Log "SKIP: Print Spooler retained (Horizon Virtual Printing may be in use)." "SKIP"; $skipped++
}

# ── SERVICES TO SET AUTOMATIC ──────────────────────────────────────────────────

# ── 8. Smart Card services (required for CAC login — Section 17) ──────────────
Write-Log "--- 8. Set Smart Card services to Automatic" "INFO"
foreach ($svc in @("SCardSvr","ScDeviceEnum")) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $s) {
        if (-not (Set-ServiceConfig -Name $svc -StartupType Automatic)) { $errors++ }
    } else {
        Write-Log "SKIP: $svc not present." "SKIP"; $skipped++
    }
}

# ── 9. FSLogix service (frxsvc) ───────────────────────────────────────────────
Write-Log "--- 9. Set FSLogix service to Automatic" "INFO"
$frxSvc = Get-Service -Name "frxsvc" -ErrorAction SilentlyContinue
if ($null -ne $frxSvc) {
    if (-not (Set-ServiceConfig -Name "frxsvc" -StartupType Automatic)) { $errors++ }
} else {
    Write-Log "SKIP: frxsvc not present (FSLogix not installed)." "SKIP"; $skipped++
}

# ── 10. DEM FlexEngine service ────────────────────────────────────────────────
Write-Log "--- 10. Set DEM FlexEngine service to Automatic" "INFO"
$demSvc = Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*DEM*" -or
                   $_.DisplayName -like "*Dynamic Environment*" -or
                   $_.DisplayName -like "*FlexEngine*" } |
    Select-Object -First 1

if ($null -ne $demSvc) {
    if (-not (Set-ServiceConfig -Name $demSvc.Name -StartupType Automatic)) { $errors++ }
} else {
    Write-Log "SKIP: DEM service not present (DEM agent not installed)." "SKIP"; $skipped++
}

# ── 11. Network Location Awareness (NLA) — critical for domain detection ──────
Write-Log "--- 11. Set NLA (NlaSvc) to Automatic" "INFO"
if (-not (Set-ServiceConfig -Name "NlaSvc" -StartupType Automatic)) { $errors++ }

Write-Log "=== Section 15 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
