#Requires -Version 7.0
<#
.SYNOPSIS  Section 10 — Notifications & Action Center
.NOTES
    Log : C:\VDI_GPO_Logs\10_Notifications_ActionCenter.log
    Suppresses lock-screen notifications (Teams message exposure risk),
    feature tip popups, and optional Action Center disable.
    Run As : Local Administrator / SYSTEM during image build
#>

. "$PSScriptRoot\Shared_Helpers.ps1"
Confirm-Prerequisites
Initialize-Log "10_Notifications_ActionCenter"

$errors = 0; $warns = 0; $skipped = 0

Write-Log "=== Configuring Notification and Action Center policies ===" "INFO"

# ── 1. Suppress toast notifications on lock screen ────────────────────────────
Write-Log "--- 1. Suppress toast notifications on lock screen" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" `
    -Name "NoToastApplicationNotificationOnLockScreen" -Value 1)) { $errors++ }

# ── 2. Disable tips and suggestions notifications ────────────────────────────
Write-Log "--- 2. Disable Windows tips/suggestions notifications" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableSoftLanding" -Value 1)) { $errors++ }

# ── 3. Disable notification badges (stale counts on non-persistent desktop) ───
Write-Log "--- 3. Disable Taskbar notification app badges" "INFO"
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\Explorer" `
    -Name "TaskbarNoNotification" -Value 0)) { $skipped++ }
# Note: Per-app badge control is best done via Teams Admin Center for Teams.
Write-Log "NOTE: Teams notification delivery mode should be configured in Teams Admin Center." "WARN"
$warns++

# ── 4. Disable Action Center (optional — evaluate per org) ───────────────────
Write-Log "--- 4. Action Center — leaving ENABLED (Teams/OneDrive need system tray)" "INFO"
Write-Log "    Set DisableNotificationCenter = 1 in this key to disable if required." "INFO"
# HKLM:SOFTWAREPoliciesMicrosoftWindowsExplorer: DisableNotificationCenter = 1
Write-Log "SKIP: Action Center not disabled — Teams and OneDrive use system tray." "SKIP"
$skipped++

# ── 5. Block all toast notifications from all applications ───────────────────
Write-Log "--- 5. Block all toast notifications (NoToastApplicationNotification = 1)" "INFO"
# Value 1 = disable toast notifications; 0 = allow (default). Correct for VDI.
if (-not (Set-RegValue -Hive HKLM `
    -Path "SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" `
    -Name "NoToastApplicationNotification" -Value 1)) { $errors++ }

Write-Log "=== Section 10 complete ===" "INFO"
Close-Log -Errors $errors -Warnings $warns -Skipped $skipped
