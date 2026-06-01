#Requires -Version 7.0
<#
.SYNOPSIS  Section 04 — OneDrive for Business (All Users / Machine-Wide)
.NOTES
    Log : C:\VDI_GPO_Logs\04_OneDrive_ForBusiness.log
    OneDrive must be installed per-machine BEFORE running this script:
        OneDriveSetup.exe /allusers
    Covers: silent SSO, Files On-Demand, tenant restriction, update ring,
            consumer client disable, KFM guidance, sync admin reports.
    Run As : Local Administrator / SYSTEM during image build

    IMPORTANT: Do NOT enable KFMSilentOptIn if DEM folder redirection is
               active for Desktop / Documents / Pictures.
               Choose ONE: DEM folder redirection OR OneDrive KFM.
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "04_OneDrive_ForBusiness"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG — Update these before deployment ────────────────────────────────────
$tenantGuid  = "YOUR-TENANT-GUID-HERE"   # <-- Your Entra / AAD Tenant GUID
$enableKFM   = $false                    # Set $true ONLY if DEM folder redir is OFF for same folders
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring OneDrive for Business policies ===" "INFO"

if ($tenantGuid -eq "YOUR-TENANT-GUID-HERE") {
    Write-Log "WARNING: tenantGuid not set. AllowTenantList and KFM will be skipped." "WARN"
    $warns++
}

# ── 1. Silent Account Configuration (SSO via Entra ID) ────────────────────────
Write-Log "--- 1. Enable Silent Account Configuration (SSO)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "SilentAccountConfig" -Value 1)) { $errors++ }

# ── 2. Files On-Demand — MANDATORY for non-persistent VDI ─────────────────────
Write-Log "--- 2. Enable Files On-Demand (mandatory for non-persistent)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "FilesOnDemandEnabled" -Value 1)) { $errors++ }

# ── 3. Restrict sync to corporate tenant ──────────────────────────────────────
Write-Log "--- 3. Set AllowTenantList (restrict to corporate Entra tenant)" "INFO"
if ($tenantGuid -ne "YOUR-TENANT-GUID-HERE") {
    $tenantKeyPath = "SOFTWARE\Policies\Microsoft\OneDrive\AllowTenantList"
    try {
        if (-not (Test-Path "HKLM:\$tenantKeyPath")) {
            New-Item -Path "HKLM:\$tenantKeyPath" -Force | Out-Null
            Write-Log "Created AllowTenantList registry key" "INFO"
        }
        Set-ItemProperty -Path "HKLM:\$tenantKeyPath" -Name $tenantGuid -Value $tenantGuid -Type String
        Write-Log "AllowTenantList: $tenantGuid configured" "SUCCESS"
    } catch {
        Write-Log "Failed to set AllowTenantList: $_" "ERROR"; $errors++
    }
} else { Write-Log "SKIP: AllowTenantList — TenantGUID not configured" "SKIP"; $skipped++ }

# ── 4. Disable personal account sync ──────────────────────────────────────────
Write-Log "--- 4. Disable personal OneDrive sync (DisablePersonalSync)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "DisablePersonalSync" -Value 1)) { $errors++ }

# ── 5. Disable consumer OneDrive client (DisableFileSyncNGSC) ─────────────────
Write-Log "--- 5. Disable consumer OneDrive client (personal MSA accounts)" "INFO"
Write-Log "    NOTE: This applies to consumer client only; OD4B is unaffected." "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\OneDrive" `
    -Name "DisableFileSyncNGSC" -Value 1)) { $errors++ }

# ── 6. Block network traffic before user sign-in ──────────────────────────────
Write-Log "--- 6. Prevent OneDrive network calls pre-logon" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "PreventNetworkTrafficPreUserSignIn" -Value 1)) { $errors++ }

# ── 7. Set update ring to Enterprise (Deferred) ───────────────────────────────
Write-Log "--- 7. Set OneDrive update ring to Enterprise/Deferred" "INFO"
# 0=Production, 1=Insiders, 2=Insiders(Slow), 3=FirstRelease, 4=Enterprise
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "GPOSetUpdateRing" -Value 4)) { $errors++ }

# ── 8. Disable OneDrive tutorial and first-run dialogs ────────────────────────
Write-Log "--- 8. Disable OneDrive tutorial and first-run dialogs" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "DisableTutorial" -Value 1)) { $errors++ }
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "DisableFirstDeleteDialog" -Value 1)) { $errors++ }

# ── 9. Enable sync admin reports (M365 Admin Center health) ───────────────────
Write-Log "--- 9. Enable OneDrive sync health admin reports" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "EnableSyncAdminReports" -Value 1)) { $errors++ }

# ── 10. KFM — Known Folder Move (conditional — DEM folder redir conflict) ──────
Write-Log "--- 10. Known Folder Move (KFM) — conditionally applied" "INFO"
if ($enableKFM) {
    Write-Log "KFM ENABLED — Ensure DEM folder redirection for Desktop/Documents/Pictures is DISABLED" "WARN"
    $warns++
    if ($tenantGuid -ne "YOUR-TENANT-GUID-HERE") {
        if (-not (Set-RegValue -Hive HKLM `
            -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
            -Name "KFMSilentOptIn" -Value $tenantGuid -Type String)) { $errors++ }
        if (-not (Set-RegValue -Hive HKLM `
            -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
            -Name "KFMBlockOptOut" -Value 1)) { $errors++ }
    }
} else {
    Write-Log "KFM SKIPPED — DEM folder redirection is active (recommended). Set enableKFM=true to enable." "SKIP"
    $skipped++
}

# ── 11. Disable OneDrive from auto-starting before user logon ─────────────────
Write-Log "--- 11. Block OneDrive pre-logon network traffic" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "PreventNetworkTrafficPreUserSignIn" -Value 1)) { $errors++ }

Write-Log "=== Section 04 complete ===" "INFO"
Write-Log "REMINDER: OneDrive must be installed via 'OneDriveSetup.exe /allusers' before this script runs." "WARN"
Write-Log "REMINDER: Verify FSLogix ODFC has IncludeOneDrive = 1 (Section 05 script)." "WARN"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
