#Requires -Version 7.0
<#
.SYNOPSIS  Section 11 — Windows Update & Patching
.NOTES
    Log : C:\VDI_GPO_Logs\11_WindowsUpdate_Patching.log
    All updates applied to golden image — NOT to running VDI sessions.
    Teams and OneDrive auto-update disabled; update rings set to Enterprise.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "11_WindowsUpdate_Patching"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Windows Update and patching policies ===" "INFO"

# ── 1. Disable Windows Auto-Update ────────────────────────────────────────────
Write-Log "--- 1. Disable in-session Windows Auto-Update" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -Name "NoAutoUpdate" -Value 1)) { $errors++ }
# AUOptions: 1=Notify only, 2=Auto-download notify install, 3=Auto-download auto-install, 4=Scheduled
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -Name "AUOptions" -Value 1)) { $errors++ }

# ── 2. Disable automatic driver updates via Windows Update ────────────────────
Write-Log "--- 2. Exclude driver updates from Windows Update" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
    -Name "ExcludeWUDriversInQualityUpdate" -Value 1)) { $errors++ }

# ── 3. Block user access to Windows Update Settings ───────────────────────────
Write-Log "--- 3. Block user access to Windows Update UI" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
    -Name "SetDisableUXWUAccess" -Value 1)) { $errors++ }

# ── 4. Disable Teams auto-update (NEW — Teams in stack) ──────────────────────
Write-Log "--- 4. Disable Teams auto-update in-session" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\MicrosoftTeams" `
    -Name "DisableAutoUpdate" -Value 1)) { $errors++ }

# ── 5. Set OneDrive update ring to Enterprise/Deferred (NEW) ─────────────────
Write-Log "--- 5. Set OneDrive update ring to Enterprise (4 = Deferred)" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\OneDrive" `
    -Name "GPOSetUpdateRing" -Value 4)) { $errors++ }

# ── 6. Disable Windows Update service auto-start (belt-and-braces) ────────────
Write-Log "--- 6. Set Windows Update service to Manual (image-level only)" "INFO"
Write-Log "    Note: wuauserv will still run when triggered by WSUS/WUfB during image build." "INFO"
# We do NOT disable this service completely — just prevent autonomous firing
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -Name "UseWUServer" -Value 0)) { $warns++ }

Write-Log "=== Section 11 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
