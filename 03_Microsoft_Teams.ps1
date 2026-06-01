#Requires -Version 7.0
<#
.SYNOPSIS  Section 03 — Microsoft Teams (New Teams 2.x, Machine-Wide)
.NOTES
    Log : C:\VDI_GPO_Logs\03_Microsoft_Teams.log
    Applies VDI-optimised Teams policies for new Teams 2.x (MSIX, machine-wide).
    Assumes Teams was deployed via Teams_windows_x64.msix with ALLUSERS=1.

    Covers:
      - Tenant restriction (block personal / competitor tenants)
      - Auto-update disabled (golden image controls versioning)
      - Outlook Meeting Add-in LoadBehavior enforcement
      - Consumer Chat icon removed from Taskbar
      - GPU acceleration disabled (reduces GPU pressure on Horizon hosts)
      - Media optimisation registry keys (Omnissa Virtualization Pack for Teams)
      - First-run / splash screen suppression

    PLACEHOLDER: Update $tenantGuid before deployment.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "03_Microsoft_Teams"

$errors = 0; $warns = 0; $skipped = 0

# ── CONFIG — must be updated before deployment ─────────────────────────────────
$tenantGuid = "YOUR-TENANT-GUID-HERE"   # <-- Your Entra ID / Azure AD Tenant GUID
# ──────────────────────────────────────────────────────────────────────────────

Write-Log "=== Configuring Microsoft Teams VDI policies ===" "INFO"

if ($tenantGuid -eq "YOUR-TENANT-GUID-HERE") {
    Write-Log "WARNING: tenantGuid placeholder not replaced. Tenant restriction will be skipped." "WARN"
    $warns++
}

# ── 1. Disable Teams auto-update (golden image controls versioning) ────────────
Write-Log "--- 1. Disable Teams auto-update" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Teams" `
    -Name "DisableAutoUpdate" -Value 1)) { $errors++ }

# Also disable via the new Teams update key
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Teams" `
    -Name "disableAutoUpdate" -Value 1)) { $warns++ }

# ── 2. Tenant restriction — block personal and competitor tenants ──────────────
Write-Log "--- 2. Configure tenant restriction" "INFO"
if ($tenantGuid -ne "YOUR-TENANT-GUID-HERE") {
    $tenantRestrictPath = "SOFTWARE\Policies\Microsoft\Teams\TenantRestrictions"
    try {
        if (-not (Test-Path "HKLM:\$tenantRestrictPath")) {
            New-Item -Path "HKLM:\$tenantRestrictPath" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\$tenantRestrictPath" -Name $tenantGuid -Value $tenantGuid -Type String
        Write-Log "Tenant restriction set for: $tenantGuid" "SUCCESS"
    } catch {
        Write-Log "Failed to set tenant restriction: $_" "ERROR"; $errors++
    }

    # Cloud policy service tenant restriction header
    if (-not (Set-RegValue -Hive HKLM `
        -Path "SOFTWARE\Policies\Microsoft\Teams" `
        -Name "CloudPolicyServiceEnabled" -Value 1)) { $warns++ }
} else {
    Write-Log "SKIP: Tenant restriction — tenantGuid not configured." "SKIP"; $skipped++
}

# ── 3. Outlook Meeting Add-in — enforce LoadBehavior = 3 (auto-load) ──────────
Write-Log "--- 3. Enforce Teams Meeting Add-in LoadBehavior = 3" "INFO"
$addinPaths = @(
    "SOFTWARE\Microsoft\Office\Teams",
    "SOFTWARE\Microsoft\Office\16.0\Outlook\Addins\TeamsAddin.FastConnect"
)
foreach ($ap in $addinPaths) {
    Set-RegValue -Hive HKLM -Path $ap -Name "LoadBehavior" -Value 3 | Out-Null
}
# Prevent Outlook from disabling the add-in under load pressure
Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList" `
    -Name "TeamsAddin.FastConnect" -Value 1 | Out-Null
Write-Log "Teams Meeting Add-in resiliency policies applied." "SUCCESS"

# ── 4. Remove consumer Chat icon from Taskbar ─────────────────────────────────
Write-Log "--- 4. Remove consumer Teams Chat icon from Taskbar" "INFO"
# ChatIcon: 0 = show, 1 = collapsed, 2 = hidden, 3 = disabled
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Windows Chat" `
    -Name "ChatIcon" -Value 3)) { $warns++ }

# ── 5. Disable GPU hardware acceleration (reduces GPU pressure on VDI hosts) ───
Write-Log "--- 5. Disable GPU hardware acceleration in Teams" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Teams" `
    -Name "DisableGpuAcceleration" -Value 1)) { $warns++ }

# Apply to default user profile so new users get it at first logon
$defaultUserHive = "C:\Users\Default\NTUSER.DAT"
if (Test-Path $defaultUserHive) {
    try {
        & reg load "HKU\DefaultUser" $defaultUserHive | Out-Null
        Set-ItemProperty -Path "Registry::HKU\DefaultUser\SOFTWARE\Microsoft\Office\Teams" `
            -Name "DisableGpuAcceleration" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Log "GPU acceleration disabled in Default User hive." "SUCCESS"
    } catch {
        Write-Log "Default user hive GPU setting failed (non-fatal): $_" "WARN"; $warns++
    } finally {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg unload "HKU\DefaultUser" | Out-Null
    }
} else {
    Write-Log "Default user hive not found at $defaultUserHive — skipping." "SKIP"; $skipped++
}

# ── 6. Omnissa Virtualization Pack for Teams — media optimisation keys ─────────
Write-Log "--- 6. Configure Omnissa Teams media optimisation registry keys" "INFO"
# These keys are read by the Virtualization Pack plugin to enable HW-accelerated
# audio/video decode on the client endpoint instead of the VDI host.
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\VMware, Inc.\VMware VDM\Client\Media" `
    -Name "OptimizedMSTeams" -Value 1)) { $warns++ }

# ── 7. Suppress Teams first-run / splash dialogs ──────────────────────────────
Write-Log "--- 7. Suppress Teams first-run experience" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Microsoft\Teams" `
    -Name "PreventFirstLaunchAfterInstall" -Value 1)) { $warns++ }

# ── 8. Disable Teams meeting diagnostics auto-submit ─────────────────────────
Write-Log "--- 8. Disable Teams diagnostic data auto-submission" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Teams" `
    -Name "DisableMeetingDiagnostics" -Value 1)) { $warns++ }

Write-Log "=== Section 03 complete ===" "INFO"
Write-Log "REMINDER: Teams must be deployed as machine-wide MSIX (ALLUSERS=1) before this script runs." "WARN"
Write-Log "REMINDER: Omnissa Virtualization Pack for Teams must be installed on the VDI host AND the endpoint client." "WARN"
Write-Log "REMINDER: Update tenantGuid placeholder and re-run if tenant restriction was skipped." "WARN"
$warns += 3
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
